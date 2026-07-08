#!/bin/bash
set -e

# Zero-Visibility Secret Pattern Implementation
# This script decrypts secrets into memory and then executes the main process.

SECRET_FILE="/run/secrets/secrets.yaml"

if [ ! -f "$SECRET_FILE" ]; then
    echo "❌ ERROR: Encrypted secrets file not found at $SECRET_FILE"
    exit 1
fi

# Function to decrypt a specific key from the SOPS yaml
decrypt_secret() {
    local key=$1
    # Use sops to decrypt and jq to extract the value
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
