#!/bin/bash
set -e

# Zero-Visibility Secret Pattern Implementation
# This script decrypts secrets into memory and then executes the main process.

SECRET_FILE="/run/secrets/secrets.yaml"

# --- Tool availability checks (fail fast) ---
for tool in sops jq; do
    if ! command -v "$tool" &>/dev/null; then
        echo "❌ ERROR: Required tool '$tool' not found in container image." >&2
        echo "   Install it or use an image that includes it." >&2
        exit 1
    fi
done

if [ ! -f "$SECRET_FILE" ]; then
    echo "❌ ERROR: Encrypted secrets file not found at $SECRET_FILE"
    exit 1
fi

# Ensure SOPS can find the Age key
if [ -n "$SOPS_AGE_KEY_FILE" ] && [ -f "$SOPS_AGE_KEY_FILE" ]; then
    export SOPS_AGE_KEY="$(cat "$SOPS_AGE_KEY_FILE")"
elif [ -z "${SOPS_AGE_KEY:-}" ]; then
    echo "❌ ERROR: No Age key found. Set SOPS_AGE_KEY or mount a key at SOPS_AGE_KEY_FILE." >&2
    exit 1
fi

# Function to decrypt a specific key from the SOPS yaml
decrypt_secret() {
    local key=$1
    sops -d "$SECRET_FILE" | jq -r ".$key // empty"
}

echo "🔐 Decrypting secrets into memory..."

# Provision SGLang secret if applicable
if [ "$SERVICE_NAME" == "sglang" ]; then
    export HF_TOKEN=$(decrypt_secret "HUGGING_FACE_HUB_TOKEN")
fi

# Provision ComfyUI secret if applicable
if [ "$SERVICE_NAME" == "comfyui" ]; then
    export COMFYUI_PASSWORD=$(decrypt_secret "COMFYUI_PASSWORD")
fi

echo "🚀 Starting $SERVICE_NAME..."
exec "$@"
