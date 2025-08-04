#!/bin/bash
# Create encrypted Tailscale secret with SOPS

set -euo pipefail

echo "🔐 Creating encrypted Tailscale secret..."

# Check if SOPS is configured
if [[ ! -f .sops.yaml ]]; then
    echo "❌ SOPS not configured. Run ./scripts/setup-sops-for-tailscale.sh first."
    exit 1
fi

# Prompt for the new auth key
echo ""
echo "📋 Please enter your new Tailscale auth key:"
echo "   (Get it from: https://login.tailscale.com/admin/settings/keys)"
echo ""
read -p "Auth key (tskey-auth-...): " NEW_AUTH_KEY

# Validate the key format
if [[ -z "$NEW_AUTH_KEY" || ! "$NEW_AUTH_KEY" =~ ^tskey-auth- ]]; then
    echo "❌ Invalid auth key format. Key should start with 'tskey-auth-'"
    exit 1
fi

# Create the encrypted secret
echo "Creating encrypted secret..."

cat > infrastructure/tailscale/base/secret.sops.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: tailscale-auth
  namespace: tailscale
  labels:
    app.kubernetes.io/name: tailscale
    app.kubernetes.io/component: subnet-router
    app.kubernetes.io/managed-by: flux
type: Opaque
stringData:
  # Tailscale auth key for k3s cluster subnet router
  # Generated: $(date)
  # Settings: Reusable=Yes, Ephemeral=No, Tags=tag:k8s
  TS_AUTHKEY: "$NEW_AUTH_KEY"
EOF

# Encrypt the secret
echo "Encrypting secret with SOPS..."
sops --encrypt --in-place infrastructure/tailscale/base/secret.sops.yaml

# Update kustomization to use the encrypted secret
echo "Updating kustomization.yaml..."
if ! grep -q "secret.sops.yaml" infrastructure/tailscale/base/kustomization.yaml; then
    # Replace secret.yaml with secret.sops.yaml in kustomization
    sed -i.bak 's/- secret.yaml/- secret.sops.yaml/' infrastructure/tailscale/base/kustomization.yaml
    echo "✅ Updated kustomization.yaml to use encrypted secret"
fi

# Remove the old plaintext secret file
if [[ -f infrastructure/tailscale/base/secret.yaml ]]; then
    rm infrastructure/tailscale/base/secret.yaml
    echo "✅ Removed old plaintext secret file"
fi

echo ""
echo "🎉 Encrypted Tailscale secret created successfully!"
echo ""
echo "Files created/updated:"
echo "  ✅ infrastructure/tailscale/base/secret.sops.yaml (encrypted)"
echo "  ✅ infrastructure/tailscale/base/kustomization.yaml (updated)"
echo "  🗑️  infrastructure/tailscale/base/secret.yaml (removed)"
echo ""
echo "Next steps:"
echo "1. Commit the changes: git add . && git commit -m 'security: Add encrypted Tailscale secret'"
echo "2. Push to repository: git push origin main"
echo "3. Flux will automatically decrypt and apply the secret"
echo ""
echo "⚠️  The old plaintext key has been revoked and removed from Git."
echo "   Your cluster will reconnect automatically with the new encrypted key."