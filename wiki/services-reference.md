# Services Reference

## SGLang (LLM Inference)

| Property | Value |
|---|---|
| Image | `lmsysorg/sglang-rocm:v0.5.14-rocm720-mi30x-20260707` |
| Container name | `inference-sglang` |
| Port | (default SGLang port, typically 30000) |
| Purpose | High-throughput LLM serving via SGLang with ROCm GPU acceleration |

### Configuration

**Environment variables:**
- `SERVICE_NAME=sglang` — Identifies the service to the entrypoint script for conditional secret loading
- `HSA_OVERRIDE_GFX_VERSION=12.0.0` — Forces gfx1201 compatibility for R9700 GPU
- `SOPS_AGE_KEY_FILE=/run/secrets/age_keys.txt` — Path for SOPS to find the Age decryption key inside the container

**GPU devices:**
```yaml
devices:
  - /dev/kfd:/dev/kfd          # ROCm compute
  - /dev/dri:/dev/dri           # DRM render node (broader mount than turnstone-stack)
```

**Command:** `python3 -m sglang.launch_server --model-path ${SGLANG_MODEL_PATH:-facebook/opt-125m} --host 0.0.0.0`

The default model is a tiny toy model (`facebook/opt-125m`) for testing. Set `SGLANG_MODEL_PATH` in `.env` to point to your actual model (HuggingFace path or local directory).

**Secrets loaded by entrypoint:**
- `HUGGING_FACE_HUB_TOKEN` — Used to authenticate with the Hugging Face Hub for gated model downloads

### Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `${SECRETS_DIR:-../turnstone-stack-secrets}/secrets.yaml` | `/run/secrets/secrets.yaml:ro` | Encrypted secrets (read-only) |
| `./scripts/` | `/scripts:ro` | Entrypoint script (read-only) |
| `${AGE_KEYS_FILE:-${HOME}/.config/sops/age/keys.txt}` | `/run/secrets/age_keys.txt:ro` | Age private key for SOPS decryption |

## ComfyUI (Visual Synthesis)

| Property | Value |
|---|---|
| Image | `ghcr.io/ai-dock/comfyui:rocm-630-latest` |
| Container name | `inference-comfyui` |
| Port | 8188 (default ComfyUI port) |
| Purpose | Stable Diffusion / image generation workflow engine with custom node support |

### Configuration

**Environment variables:**
- `SERVICE_NAME=comfyui` — Identifies the service to the entrypoint script for conditional secret loading
- `HSA_OVERRIDE_GFX_VERSION=12.0.0` — Forces gfx1201 compatibility for R9700 GPU
- `SOPS_AGE_KEY_FILE=/run/secrets/age_keys.txt` — Path for SOPS Age key inside container

**GPU devices:** Same as SGLang (`/dev/kfd`, `/dev/dri`).

**Command:** `python3 main.py --listen 0.0.0.0`

**Secrets loaded by entrypoint:**
- `COMFYUI_PASSWORD` — Web UI login password (decrypted from secrets.yaml)

### Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./comfyui/models/` | `/home/user/comfyui/models` | Checkpoints, LoRAs, ControlNets, etc. |
| `./comfyui/input/` | `/home/user/comfyui/input` | Input images for workflows |
| `./comfyui/output/` | `/home/user/comfyui/output` | Generated image output |
| `${DOCS_ASSETS:-${HOME}/docs/assets}` | `/home/user/comfyui/output_shared:rw` | Shared assets directory — generated images also appear here for use by other services (e.g., Obsidian notes, Turnstone) |

The `output_shared` mount is a convenience feature that makes ComfyUI output accessible from the host's docs directory.

## Tailscale Sidecar

| Property | Value |
|---|---|
| Image | `tailscale/tailscale:v1.78.0` |
| Container name | `inference-tailscale` |
| Hostname | `${INFERENCE_HOSTNAME:-inference-stack}` |
| Purpose | Tailscale networking identity for the inference stack — separate from turnstone-stack's Tailscale container |

### Configuration

- State volume: `./tailscale_state/` → `/var/lib/tailscale` (persists across restarts)
- Auth key: `${SECRETS_DIR:-../turnstone-stack-secrets}/.ts_authkey` mounted read-only at `/run/secrets/ts_authkey`
- TUN device: `/dev/net/tun:/dev/net/tun`
- Capabilities: `NET_ADMIN`, `SYS_MODULE` (required for WireGuard tunnel)

Other services in the stack use `network_mode: "service:tailscale"` to share this network namespace.

## Entrypoint Script (`scripts/entrypoint.sh`)

All inference services use a shared entrypoint that implements the Zero-Visibility Secret Pattern:

1. **Tool check** — Verifies `sops` and `jq` are available in the container image
2. **Key setup** — Reads the Age key file into `SOPS_AGE_KEY` env var (avoids discovery issues)
3. **Conditional decryption** — Based on `$SERVICE_NAME`:
   - `sglang` → decrypts `HUGGING_FACE_HUB_TOKEN` from secrets.yaml
   - `comfyui` → decrypts `COMFYUI_PASSWORD` from secrets.yaml
4. **Exec** — Runs the main application command with `exec "$@"` (replaces shell process)

```bash
decrypt_secret() {
    local key=$1
    sops -d "$SECRET_FILE" | jq -r ".$key // empty"
}
```

This approach keeps secrets in memory only — they're never written to disk inside the container and don't appear in `docker inspect`.
