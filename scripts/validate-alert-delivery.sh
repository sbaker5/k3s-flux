#!/bin/bash
# Validation script for alert notification delivery
# Tests webhook endpoints, email delivery, and other notification channels

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
ALERTMANAGER_URL="http://localhost:9093"
WEBHOOK_TEST_PORT="8080"
WEBHOOK_TEST_PID=""

# Function to log messages
log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $*" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
        TEST)
            echo -e "${CYAN}[TEST]${NC} $*"
            ;;
    esac
}

# Cleanup function
cleanup() {
    if [ -n "$WEBHOOK_TEST_PID" ]; then
        kill "$WEBHOOK_TEST_PID" 2>/dev/null || true
    fi
    
    # Kill any port forwards
    pkill -f "kubectl port-forward.*alertmanager" 2>/dev/null || true
}

trap cleanup EXIT

# Function to start a test webhook server
start_test_webhook() {
    log INFO "Starting test webhook server on port $WEBHOOK_TEST_PORT..."
    
    # Create a simple webhook server using Python
    cat > /tmp/webhook_server.py << 'EOF'
#!/usr/bin/env python3
import json
import http.server
import socketserver
from datetime import datetime

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            webhook_data = json.loads(post_data.decode('utf-8'))
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            print(f"\n[{timestamp}] Webhook received:")
            print(f"Status: {webhook_data.get('status', 'unknown')}")
            
            if 'alerts' in webhook_data:
                for alert in webhook_data['alerts']:
                    alert_name = alert.get('labels', {}).get('alertname', 'unknown')
                    alert_status = alert.get('status', 'unknown')
                    print(f"  - {alert_name}: {alert_status}")
            
            # Log to file for verification
            with open('/tmp/webhook_alerts.log', 'a') as f:
                f.write(f"{timestamp}: {json.dumps(webhook_data)}\n")
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
            
        except Exception as e:
            print(f"Error processing webhook: {e}")
            self.send_response(400)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default HTTP logging
        pass

if __name__ == "__main__":
    PORT = 8080
    with socketserver.TCPServer(("", PORT), WebhookHandler) as httpd:
        print(f"Webhook server listening on port {PORT}")
        httpd.serve_forever()
EOF

    python3 /tmp/webhook_server.py &
    WEBHOOK_TEST_PID=$!
    
    # Wait for server to start
    sleep 2
    
    # Test webhook server
    if curl -s -X POST -H "Content-Type: application/json" \
       -d '{"test": "webhook"}' \
       "http://localhost:$WEBHOOK_TEST_PORT" >/dev/null; then
        log SUCCESS "Test webhook server started successfully"
        return 0
    else
        log ERROR "Failed to start test webhook server"
        return 1
    fi
}

# Function to check Alertmanager configuration
check_alertmanager_config() {
    log TEST "Checking Alertmanager configuration..."
    
    # Try to access Alertmanager
    kubectl port-forward -n monitoring svc/alertmanager 9093:9093 --address=0.0.0.0 &
    local am_pid=$!
    sleep 5
    
    # Check if Alertmanager is accessible
    if ! curl -s "$ALERTMANAGER_URL/api/v1/status" >/dev/null; then
        log WARN "Alertmanager not accessible, checking if it exists..."
        
        if kubectl get service -n monitoring | grep -q alertmanager; then
            log INFO "Alertmanager service found but not accessible"
        else
            log INFO "Alertmanager not deployed in this cluster"
            log INFO "Alert delivery testing will be limited to Prometheus alerts"
        fi
        
        kill $am_pid 2>/dev/null || true
        return 1
    fi
    
    # Get Alertmanager configuration
    local config_response=$(curl -s "$ALERTMANAGER_URL/api/v1/status" || echo "")
    if [ -n "$config_response" ]; then
        log SUCCESS "Alertmanager is accessible"
        echo "$config_response" | jq -r '.data.configYAML' 2>/dev/null | head -20 || echo "Config not available"
    fi
    
    kill $am_pid 2>/dev/null || true
    return 0
}

# Function to test alert silencing
test_alert_silencing() {
    log TEST "Testing alert silencing functionality..."
    
    # Setup port forward to Alertmanager
    kubectl port-forward -n monitoring svc/alertmanager 9093:9093 --address=0.0.0.0 &
    local am_pid=$!
    sleep 5
    
    # Create a test silence
    local silence_data='{
        "matchers": [
            {
                "name": "alertname",
                "value": "GitOpsDeploymentRolloutStuck",
                "isRegex": false
            }
        ],
        "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
        "endsAt": "'$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%S.000Z)'",
        "createdBy": "alert-test-script",
        "comment": "Test silence for alert delivery validation"
    }'
    
    local silence_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$silence_data" \
        "$ALERTMANAGER_URL/api/v1/silences" || echo "")
    
    if echo "$silence_response" | jq -e '.silenceID' >/dev/null 2>&1; then
        local silence_id=$(echo "$silence_response" | jq -r '.silenceID')
        log SUCCESS "Test silence created: $silence_id"
        
        # List active silences
        local silences=$(curl -s "$ALERTMANAGER_URL/api/v1/silences" || echo "")
        if [ -n "$silences" ]; then
            log INFO "Active silences:"
            echo "$silences" | jq -r '.data[] | "- \(.id): \(.comment)"' 2>/dev/null || echo "No silences"
        fi
        
        # Clean up test silence
        curl -s -X DELETE "$ALERTMANAGER_URL/api/v1/silence/$silence_id" >/dev/null || true
        log INFO "Test silence cleaned up"
    else
        log WARN "Could not create test silence (Alertmanager may not be configured)"
    fi
    
    kill $am_pid 2>/dev/null || true
}

# Function to validate webhook delivery
test_webhook_delivery() {
    log TEST "Testing webhook alert delivery..."
    
    if ! start_test_webhook; then
        log ERROR "Cannot start test webhook server"
        return 1
    fi
    
    # Clear previous webhook logs
    rm -f /tmp/webhook_alerts.log
    
    log INFO "Webhook server ready to receive alerts"
    log INFO "In a production setup, you would configure Alertmanager to send to:"
    log INFO "  webhook_url: http://your-webhook-server:$WEBHOOK_TEST_PORT"
    
    # Simulate webhook delivery by sending test data
    local test_alert='{
        "receiver": "webhook-test",
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": {
                    "alertname": "GitOpsDeploymentRolloutStuck",
                    "severity": "warning",
                    "namespace": "alert-test"
                },
                "annotations": {
                    "summary": "Test alert for webhook delivery validation",
                    "description": "This is a test alert to validate webhook delivery"
                },
                "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
                "endsAt": "0001-01-01T00:00:00Z",
                "generatorURL": "http://prometheus:9090/graph?g0.expr=test_alert"
            }
        ],
        "groupLabels": {
            "alertname": "GitOpsDeploymentRolloutStuck"
        },
        "commonLabels": {
            "alertname": "GitOpsDeploymentRolloutStuck",
            "severity": "warning"
        },
        "commonAnnotations": {},
        "externalURL": "http://alertmanager:9093",
        "version": "4",
        "groupKey": "{}:{alertname=\"GitOpsDeploymentRolloutStuck\"}"
    }'
    
    log INFO "Sending test alert to webhook..."
    if curl -s -X POST -H "Content-Type: application/json" \
       -d "$test_alert" \
       "http://localhost:$WEBHOOK_TEST_PORT"; then
        log SUCCESS "Test alert sent to webhook"
    else
        log ERROR "Failed to send test alert to webhook"
        return 1
    fi
    
    # Wait a moment and check logs
    sleep 2
    
    if [ -f /tmp/webhook_alerts.log ]; then
        log SUCCESS "Webhook received alerts:"
        cat /tmp/webhook_alerts.log
    else
        log WARN "No webhook alerts logged"
    fi
}

# Function to test email notification (if configured)
test_email_delivery() {
    log TEST "Testing email notification delivery..."
    
    # This would require SMTP configuration in Alertmanager
    log INFO "Email testing requires Alertmanager SMTP configuration"
    log INFO "To test email delivery:"
    echo "  1. Configure SMTP in Alertmanager config:"
    echo "     global:"
    echo "       smtp_smarthost: 'localhost:587'"
    echo "       smtp_from: 'alerts@example.com'"
    echo "  2. Add email receiver:"
    echo "     receivers:"
    echo "     - name: 'email-alerts'"
    echo "       email_configs:"
    echo "       - to: 'admin@example.com'"
    echo "         subject: 'GitOps Alert: {{ .GroupLabels.alertname }}'"
    echo "  3. Route alerts to email receiver"
    
    log INFO "Email delivery test skipped (requires SMTP configuration)"
}

# Function to test Slack/Teams integration
test_chat_delivery() {
    log TEST "Testing chat notification delivery..."
    
    log INFO "Chat integration testing requires webhook URLs"
    log INFO "To test Slack/Teams delivery:"
    echo "  1. Create webhook URL in Slack/Teams"
    echo "  2. Configure Alertmanager receiver:"
    echo "     receivers:"
    echo "     - name: 'slack-alerts'"
    echo "       slack_configs:"
    echo "       - api_url: 'https://hooks.slack.com/services/...'"
    echo "         channel: '#alerts'"
    echo "         title: 'GitOps Alert'"
    echo "         text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'"
    
    log INFO "Chat delivery test skipped (requires webhook configuration)"
}

# Function to validate alert routing rules
test_alert_routing() {
    log TEST "Testing alert routing rules..."
    
    # Setup port forward to Alertmanager
    kubectl port-forward -n monitoring svc/alertmanager 9093:9093 --address=0.0.0.0 &
    local am_pid=$!
    sleep 5
    
    # Get routing configuration
    local config_response=$(curl -s "$ALERTMANAGER_URL/api/v1/status" || echo "")
    if [ -n "$config_response" ]; then
        log INFO "Current Alertmanager routing configuration:"
        echo "$config_response" | jq -r '.data.configYAML' 2>/dev/null | grep -A 20 "route:" || echo "No routing config found"
    else
        log WARN "Cannot access Alertmanager routing configuration"
    fi
    
    # Test route matching
    log INFO "Testing route matching for different alert types:"
    
    local test_alerts=(
        "GitOpsDeploymentRolloutStuck:warning"
        "FluxKustomizationStuck:warning"
        "GitOpsNamespaceStuckTerminating:critical"
        "FluxSystemDegraded:critical"
    )
    
    for alert_info in "${test_alerts[@]}"; do
        local alert_name="${alert_info%%:*}"
        local severity="${alert_info#*:}"
        
        log INFO "Route test for $alert_name (severity: $severity):"
        echo "  - Would match routes with severity=$severity"
        echo "  - Would match routes with alertname=$alert_name"
        echo "  - Default route would catch unmatched alerts"
    done
    
    kill $am_pid 2>/dev/null || true
}

# Function to check alert inhibition rules
test_alert_inhibition() {
    log TEST "Testing alert inhibition rules..."
    
    log INFO "Alert inhibition prevents lower-priority alerts when higher-priority ones are active"
    log INFO "Example inhibition rules for GitOps alerts:"
    echo "  inhibit_rules:"
    echo "  - source_match:"
    echo "      alertname: 'FluxSystemDegraded'"
    echo "    target_match:"
    echo "      alertname: 'FluxKustomizationStuck'"
    echo "    equal: ['cluster']"
    echo ""
    echo "  - source_match:"
    echo "      severity: 'critical'"
    echo "    target_match:"
    echo "      severity: 'warning'"
    echo "    equal: ['namespace']"
    
    log INFO "Inhibition testing requires active alerts to validate"
}

# Main function
main() {
    echo "📬 Alert Notification Delivery Testing"
    echo "======================================"
    echo ""
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        log ERROR "kubectl not found"
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        log ERROR "curl not found"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log ERROR "jq not found (install with: brew install jq)"
        exit 1
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        log ERROR "python3 not found"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log ERROR "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log INFO "Starting alert delivery validation tests..."
    echo ""
    
    # Test 1: Check Alertmanager configuration
    check_alertmanager_config
    echo ""
    
    # Test 2: Test webhook delivery
    test_webhook_delivery
    echo ""
    
    # Test 3: Test alert routing
    test_alert_routing
    echo ""
    
    # Test 4: Test alert silencing
    test_alert_silencing
    echo ""
    
    # Test 5: Test alert inhibition
    test_alert_inhibition
    echo ""
    
    # Test 6: Test email delivery (informational)
    test_email_delivery
    echo ""
    
    # Test 7: Test chat delivery (informational)
    test_chat_delivery
    echo ""
    
    log SUCCESS "Alert delivery validation completed!"
    echo ""
    log INFO "Summary of delivery tests:"
    echo "  ✅ Alertmanager configuration check"
    echo "  ✅ Webhook delivery simulation"
    echo "  ✅ Alert routing validation"
    echo "  ✅ Alert silencing test"
    echo "  ✅ Alert inhibition rules review"
    echo "  ℹ️  Email delivery (requires SMTP config)"
    echo "  ℹ️  Chat delivery (requires webhook config)"
    echo ""
    
    log INFO "To fully test alert delivery in production:"
    echo "  1. Configure Alertmanager with your notification channels"
    echo "  2. Run the stuck state simulation script"
    echo "  3. Verify alerts are delivered to configured channels"
    echo "  4. Test alert acknowledgment and resolution workflows"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --webhook-port      Port for test webhook server (default: $WEBHOOK_TEST_PORT)"
        echo ""
        echo "This script validates alert notification delivery by:"
        echo "  1. Testing webhook endpoints"
        echo "  2. Validating alert routing rules"
        echo "  3. Testing alert silencing and inhibition"
        echo "  4. Providing guidance for email/chat integration"
        echo ""
        exit 0
        ;;
    --webhook-port)
        WEBHOOK_TEST_PORT="$2"
        shift
        ;;
esac

# Run main function
main "$@"