#!/bin/bash
set -e

# --- Configuration ---
STACK_DIR="/opt/data/home/inference-stack"
SECRETS_DIR="/opt/data/home/turnstone-stack-secrets"
DOCS_ASSETS="/opt/data/docs/assets"

echo "🚀 Starting Inference Stack Setup..."

# 1. Verify ROCm Drivers / GPU Access
rocm_ok=false

# Native Linux: check for /dev/kfd character device
if [ -c /dev/kfd ]; then
    rocm_ok=true
fi

# WSL2 with AMD HIP/ROCm user-space drivers: rocminfo works via HSARunner without /dev/kfd
# Search common install locations since Windows installer may not add to PATH
for rocminfo_path in $(find /opt/rocm* /usr/local /snap -maxdepth 4 -name "rocminfo" -type f 2>/dev/null); do
    # Match GPU agent specifically (Device Type: GPU), not the CPU which also says "AMD"
    gpu_info=$("$rocminfo_path" 2>/dev/null | awk '/Agent [0-9]/{agent=""} /Marketing Name.*AMD/{gpu=1; agent=$0} /Device Type.*GPU/{if(gpu) print agent; gpu=0}' | head -1)
    if [ -n "$gpu_info" ]; then
        rocm_ok=true
        echo "✅ WSL environment detected — ROCm GPU found via HSARunner: $gpu_info"
        break
    fi
done

if [ "$rocm_ok" = false ]; then
    echo "❌ ERROR: AMD ROCm drivers not found (/dev/kfd missing, rocminfo unavailable)."
    echo "Please install the ROCm kernel drivers on your host system."
    exit 1
fi

if [ "$rocm_ok" = true ] && [ ! -c /dev/kfd ]; then
    : # already printed WSL message above
elif [ "$rocm_ok" = true ]; then
    echo "✅ ROCm drivers detected (/dev/kfd)."
fi

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

# Continue setup with helpful next steps instead of exit
echo "" >&2
if [ ! -f "$SECRETS_DIR/common/secrets.yaml" ] || [ ! -s "$SECRETS_DIR/common/secrets.yaml" ]; then
    echo "⚠️  WARNING: Secrets file not found or empty at $SECRETS_DIR/common/secrets.yaml" >&2
fi

echo "" >&2
echo "📝 Next steps:" >&2
echo "   1. Copy real TS_AUTHKEY from turnstone-stack-secrets:" >&2
echo "      cp ../turnstone-stack-secrets/.ts_authkey ./secrets/ts_authkey" >&2
echo "   2. Add HUGGING_FACE_HUB_TOKEN and COMFYUI_PASSWORD to secrets.yaml" >&2
echo "" >&2
echo "✨ Inference Stack setup complete! Run: docker compose up -d"

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
