#!/bin/bash
# Setup SOPS encryption for Tailscale secrets

set -euo pipefail

echo "🔐 Setting up SOPS encryption for Tailscale secrets..."

# Check if SOPS is installed
if ! command -v sops &> /dev/null; then
    echo "Installing SOPS via Homebrew..."
    brew install sops
fi

# Check if age is installed
if ! command -v age &> /dev/null; then
    echo "Installing age via Homebrew..."
    brew install age
fi

# Generate age key if it doesn't exist
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
if [[ ! -f "$AGE_KEY_FILE" ]]; then
    echo "Generating new age key..."
    mkdir -p "$(dirname "$AGE_KEY_FILE")"
    age-keygen -o "$AGE_KEY_FILE"
    echo "✅ Age key generated: $AGE_KEY_FILE"
else
    echo "✅ Age key already exists: $AGE_KEY_FILE"
fi

# Get the public key
PUBLIC_KEY=$(grep "# public key:" "$AGE_KEY_FILE" | cut -d' ' -f4)
echo "📋 Your public key: $PUBLIC_KEY"

# Create .sops.yaml configuration
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: \.sops\.yaml$
    age: $PUBLIC_KEY
  - path_regex: infrastructure/tailscale/.*\.sops\.yaml$
    age: $PUBLIC_KEY
EOF

echo "✅ SOPS configuration created: .sops.yaml"

# Create Kubernetes secret for SOPS in the cluster
echo "Creating Kubernetes secret for SOPS decryption..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

# Get the private key (without the public key comment)
PRIVATE_KEY=$(grep -v "^#" "$AGE_KEY_FILE")

kubectl create secret generic sops-age \
    --namespace=flux-system \
    --from-literal=age.agekey="$PRIVATE_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ SOPS age secret created in flux-system namespace"

echo ""
echo "🎉 SOPS setup complete!"
echo ""
echo "Next steps:"
echo "1. Get your new Tailscale auth key from: https://login.tailscale.com/admin/settings/keys"
echo "2. Run: ./scripts/create-encrypted-tailscale-secret.sh"
echo ""
echo "⚠️  IMPORTANT: Keep your age key file ($AGE_KEY_FILE) secure and backed up!"