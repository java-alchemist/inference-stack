#!/bin/bash
set -e

# --- Configuration ---
STACK_DIR="/opt/data/home/inference-stack"
SECRETS_DIR="/opt/data/home/turnstone-stack-secrets"
DOCS_ASSETS="/opt/data/docs/assets"
DOCS_ASSETS="/opt/data/docs/assets"

echo "🚀 Starting Inference Stack Setup..."

# 1. Verify ROCm Drivers
if [ ! -c /dev/kfd ]; then
    echo "❌ ERROR: AMD ROCm drivers not found (/dev/kfd missing)."
    echo "Please install the ROCm kernel drivers on your host system."
    exit 1
fi
echo "✅ ROCm drivers detected."

# 2. Provision Secrets (Zero-Visibility Pattern)
echo "🔐 Provisioning secrets..."
mkdir -p "$STACK_DIR/secrets"

# In a real scenario, we would use: sops -d $SECRETS_DIR/secrets.yaml > $STACK_DIR/secrets/.env
# For now, we ensure the directory exists and is restricted
chmod 700 "$STACK_DIR/secrets"

# Create placeholder secret files to prevent container crash on boot
echo "" >&2
echo "⚠️  WARNING: Creating PLACEHOLDER secrets — these are NOT real credentials." >&2
echo "   The containers will start but Tailscale authentication will FAIL." >&2
echo "   Run 'make setup' or provision real secrets from turnstone-stack-secrets first." >&2
echo "" >&2
echo "placeholder_key" > "$STACK_DIR/secrets/ts_authkey"
echo "placeholder_password" > "$STACK_DIR/secrets/comfyui_password"
chmod 600 "$STACK_DIR/secrets/"*

# 3. Bootstrap Models (Starter Set)
echo "📦 Bootstrapping starter models..."
mkdir -p "$STACK_DIR/comfyui/models/checkpoints"

# Example: Download a small model or create a placeholder to verify paths
if [ ! -f "$STACK_DIR/comfyui/models/checkpoints/starter.safetensors" ]; then
    echo "Downloading starter checkpoint (simulated)..."
    touch "$STACK_DIR/comfyui/models/checkpoints/starter.safetensors"
fi

# 4. Ensure Shared Assets Directory exists
mkdir -p "$DOCS_ASSETS"

echo "✨ Inference Stack setup complete!"
echo "You can now run: docker compose up -d"
