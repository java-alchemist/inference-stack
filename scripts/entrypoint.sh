#!/bin/bash
set -e

# =============================================================================
# Zero-Visibility Secret Pattern Implementation for Inference Stack
# =============================================================================
# This script decrypts secrets into memory and validates them before starting.
# Secrets never appear in docker inspect or logs (except when echoed by app).
# =============================================================================

SECRET_FILE="/run/secrets/secrets.yaml"

# --- Tool availability checks (fail fast) ---
for tool in sops jq; do
    if ! command -v "$tool" &>/dev/null; then
        echo "❌ ERROR: Required tool '$tool' not found in container image." >&2
        echo "   Install it or use an image that includes it (e.g., python3 + sops)." >&2
        exit 1
    fi
done

if [ ! -f "$SECRET_FILE" ]; then
    echo "❌ ERROR: Encrypted secrets file not found at $SECRET_FILE" >&2
    echo "   Expected path: /run/secrets/secrets.yaml (mount from host)" >&2
    exit 1
fi

# Ensure SOPS can find the Age key
if [ -n "$SOPS_AGE_KEY_FILE" ] && [ -f "$SOPS_AGE_KEY_FILE" ]; then
    export SOPS_AGE_KEY="$(cat "$SOPS_AGE_KEY_FILE")"
elif [ -z "${SOPS_AGE_KEY:-}" ]; then
    echo "❌ ERROR: No Age key found." >&2
    echo "   Set SOPS_AGE_KEY env var or mount a key at \$SOPS_AGE_KEY_FILE" >&2
    exit 1
fi

# --- Secret Validation Functions ---

validate_huggingface_token() {
    local token="$1"
    
    if [ -z "$token" ]; then
        echo "❌ ERROR: HUGGING_FACE_HUB_TOKEN not found or empty in secrets.yaml" >&2
        echo "   Add it to turnstone-stack-secrets/common/secrets.yaml:" >&2
        echo "" >&2
        echo "   HF_TOKEN=<your-huggingface-token>" >&2
        echo "" >&2
        echo "   Then re-encrypt with: sops --age <pubkey> --encrypt common/secrets.yaml" >&2
        exit 1
    fi
    
    # Optional: Validate token format (HuggingFace tokens are typically 40-char alphanumeric with underscores)
    if ! [[ "$token" =~ ^[A-Za-z0-9_-]{36,}$ ]]; then
        echo "⚠️  WARNING: HUGGING_FACE_HUB_TOKEN format looks unusual." >&2
        echo "   Expected ~40 characters (alphanumeric + underscore). Got ${#token} chars." >&2
        echo "   Verify the token is correct before proceeding." >&2
    fi
    
    return 0
}

validate_comfyui_password() {
    local password="$1"
    
    if [ -z "$password" ]; then
        echo "❌ ERROR: COMFYUI_PASSWORD not found or empty in secrets.yaml" >&2
        echo "   Add it to turnstone-stack-secrets/common/secrets.yaml:" >&2
        echo "" >&2
        echo "   COMFYUI_PASSWORD=<your-password>" >&2
        echo "" >&2
        echo "   Then re-encrypt with: sops --age <pubkey> --encrypt common/secrets.yaml" >&2
        exit 1
    fi
    
    # Optional: Warn if password is too short (basic validation)
    if [ ${#password} -lt 8 ]; then
        echo "⚠️  WARNING: COMFYUI_PASSWORD appears to be very short (${#password} chars)." >&2
        echo "   Consider using a stronger password for production." >&2
    fi
    
    return 0
}

validate_tailscale_auth() {
    if [ -z "${TS_AUTHKEY:-}" ]; then
        # Tailscale container handles its own auth, but warn if key is missing
        echo "⚠️  WARNING: TS_AUTHKEY not set. Tailscale container may fail to connect to Tailnet." >&2
        return 0  # Don't fail hard - tailscale will provide better error
    fi
    
    # Basic validation that authkey has some content
    if [ ${#TS_AUTHKEY} -lt 10 ]; then
        echo "⚠️  WARNING: TS_AUTHKEY appears to be incomplete (${#TS_AUTHKEY} chars)." >&2
    fi
    
    return 0
}

echo "🔐 Decrypting secrets into memory..."

# --- Provision Secrets Based on Service Type ---

if [ -z "${SERVICE_NAME:-}" ]; then
    echo "❌ ERROR: SERVICE_NAME not set. This script requires SERVICE_NAME=sglang or SERVICE_NAME=comfyui" >&2
    exit 1
fi

case "$SERVICE_NAME" in
    sglang)
        # Decrypt HuggingFace token for SGLang model downloads
        export HF_TOKEN="$(sops -d "$SECRET_FILE" | jq -r '.HUGGING_FACE_HUB_TOKEN // empty')"
        
        echo "  🔑 Provisioning HUGGING_FACE_HUB_TOKEN..."
        validate_huggingface_token "$HF_TOKEN"
        ;;
    
    comfyui)
        # Decrypt ComfyUI password for web UI login
        export COMFYUI_PASSWORD="$(sops -d "$SECRET_FILE" | jq -r '.COMFYUI_PASSWORD // empty')"
        
        echo "  🔑 Provisioning COMFYUI_PASSWORD..."
        validate_comfyui_password "$COMFYUI_PASSWORD"
        ;;
    
    *)
        # For other services or if SERVICE_NAME is not recognized
        if [ -f "/run/secrets/ts_authkey" ]; then
            export TS_AUTHKEY="$(cat /run/secrets/ts_authkey)"
            echo "  🔑 Provisioning TS_AUTHKEY for Tailscale..."
            validate_tailscale_auth
        fi
        ;;
esac

# --- Final Validation Summary ---

echo "" >&2
echo "✅ Secrets validated successfully for $SERVICE_NAME" >&2
echo "" >&2
echo "📋 Active environment variables:" >&2
case "$SERVICE_NAME" in
    sglang) echo "  • HF_TOKEN=${HF_TOKEN:0:8}*** (masked)" ;;
    comfyui) echo "  • COMFYUI_PASSWORD=*${COMFYUI_PASSWORD: -3}" ;;
esac

echo "" >&2
echo "🚀 Starting $SERVICE_NAME..." >&2
echo "" >&2

# Execute the main application process
exec "$@"
