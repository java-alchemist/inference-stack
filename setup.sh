#!/bin/bash
set -e

# --- Configuration ---
# Resolve paths relative to this script's directory (works regardless of where it's cloned)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR"
SECRETS_SIBLING="$SCRIPT_DIR/../turnstone-stack-secrets"

TEMP_FILES=()  # Track temp files for cleanup
cleanup() {
    rm -f "${TEMP_FILES[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

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

# --- 2. Clone/Update Secrets Repo ---
if [ ! -d "$SECRETS_SIBLING/.git" ]; then
    echo "📂 Cloning secrets repository..."
    git clone https://github.com/java-alchemist/turnstone-stack-secrets.git "$SECRETS_SIBLING" || {
        echo "❌ Failed to clone secrets repo" >&2; exit 1
    }
else
    echo "ℹ️  Secrets repo already present, pulling latest..."
    cd "$SECRETS_SIBLING" && git pull --quiet 2>&1 || true
    cd "$STACK_DIR" > /dev/null
fi

# --- 3. Decrypt secrets via Docker (mirrors turnstone-stack) ---
CONFIG_DIR="$HOME/.config/sops"
KEYS_FILE="$CONFIG_DIR/age/keys.txt"
COMMON_SECRETS="common/secrets.yaml"
ABS_STACK_DIR="$(cd "$STACK_DIR" && pwd)"
ABS_PWD="$ABS_STACK_DIR"
ABS_SECRETS_DIR="$(cd "$SECRETS_SIBLING" && pwd)"

# Check for Age key
if [ ! -f "$KEYS_FILE" ]; then
    echo "❌ No SOPS Age key found at $KEYS_FILE" >&2
    echo "   Run setup in turnstone-stack first to generate one." >&2
    exit 1
fi

decrypt_sops() {
    docker run --rm \
        -v "$ABS_PWD:/work" \
        -v "$ABS_SECRETS_DIR:/secrets" \
        -v "$KEYS_FILE:/run/age/key:ro" \
        -e SOPS_AGE_KEY_FILE=/run/age/key \
        -w /work ghcr.io/getsops/sops:v3.9.4 \
        --decrypt /secrets/$COMMON_SECRETS
}

TEMP_DECRYPTED=".tmp_decrypted.yaml"
TEMP_FILES+=("$TEMP_DECRYPTED")

echo "📦 Decrypting secrets..."
# Capture stderr separately so we can show the real SOPS error on failure
TEMP_ERR=".tmp_decrypt_err"
TEMP_FILES+=("$TEMP_ERR")

echo "📦 Decrypting secrets..."
if decrypt_sops > "$TEMP_DECRYPTED" 2>"$TEMP_ERR"; then
    echo "✅ Decryption successful."
else
    ERR_MSG=$(cat "$TEMP_ERR" 2>/dev/null)
    if [ -n "$ERR_MSG" ]; then
        echo "❌ Decryption failed:" >&2
        echo "$ERR_MSG" >&2
    else
        echo "❌ Decryption failed. Check that your Age key matches the recipient in .sops.yaml" >&2
    fi
    exit 1
fi

# Parse decrypted YAML into individual secret files
mkdir -p "$STACK_DIR/secrets"
chmod 700 "$STACK_DIR/secrets"

provision() {
    local var="$1"; local file="$2"
    local val=$(grep "^${var}:" "$TEMP_DECRYPTED" | head -1 | cut -d' ' -f2- | tr -d '"' "'"')
    if [ -n "$val" ]; then
        printf '%s' "$val" > "$STACK_DIR/secrets/$file"
        chmod 600 "$STACK_DIR/secrets/$file"
        echo "  ✅ $var → secrets/$file"
    fi
}

provision "TS_AUTHKEY" ".ts_authkey"
provision "COMFYUI_PASSWORD" ".comfyui_password"
provision "HERMES_API_KEY" ".hermes_key"

# 4. Bootstrap Models (Starter Set)
echo "📦 Preparing model directories..."
mkdir -p "$STACK_DIR/comfyui/models/checkpoints"

echo "" >&2
echo "✨ Inference Stack setup complete!" >&2
echo "   Run 'make up-sglang' or 'make up-comfy' to start services."
