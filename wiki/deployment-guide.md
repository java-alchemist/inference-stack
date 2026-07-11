# Deployment Guide

## Prerequisites

- **Docker Engine** with Compose plugin v2
- **ROCm kernel drivers** — `/dev/kfd` and `/dev/dri/renderD128` must exist for AMD GPU passthrough
- **Tailscale machine auth key** in `turnstone-stack-secrets/.ts_authkey`
- **Age private key** at `~/.config/sops/age/keys.txt` (shared with turnstone-stack)
- Access to the shared `turnstone-stack-secrets` repository

## Directory Structure

```
inference-stack/
├── .env.example           # Configuration template
├── docker-compose.yml     # Full stack: SGLang + ComfyUI together
├── docker-compose.sglang.yml   # LLM inference session only
├── docker-compose.comfy.yml    # Image generation session only
├── scripts/
│   └── entrypoint.sh      # Zero-visibility secret decryption at startup
├── setup.sh               # Bootstrap script (ROCm check, placeholder secrets)
├── Makefile               # Management targets
└── .gitignore             # Excludes data dirs and secrets
```

## Configuration

Copy `.env.example` to `.env` and adjust values:

```bash
cp .env.example .env
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SECRETS_DIR` | `../turnstone-stack-secrets` | Path to the shared secrets repo (relative or absolute) |
| `AGE_KEYS_FILE` | `${HOME}/.config/sops/age/keys.txt` | Age private key for SOPS decryption |
| `DOCS_ASSETS` | `${HOME}/docs/assets` | Shared output directory for ComfyUI generated images |
| `SGLANG_MODEL_PATH` | `facebook/opt-125m` | HuggingFace model path or local directory for SGLang |
| `INFERENCE_HOSTNAME` | `inference-stack` | Tailscale hostname for the inference stack identity |

## Makefile Targets

```bash
# Setup (ROCm check + placeholder secrets warning)
make setup

# Session-based launch — choose ONE at a time:
make up-sglang     # Start SGLang LLM server + Tailscale sidecar
make down-sglang   # Stop SGLang

make up-comfy      # Start ComfyUI image generation + Tailscale sidecar
make down-comfy    # Stop Comfyui

# Check running inference containers
make status
```

## Launching with Specific Compose Files

The Makefile targets use individual compose files for session isolation:

```bash
# SGLang only (LLM inference)
docker compose -f docker-compose.sglang.yml up -d

# ComfyUI only (image generation)
docker compose -f docker-compose.comfy.yml up -d

# Both together (requires sufficient VRAM — not recommended on 32GB card)
docker compose -f docker-compose.yml up -d
```

## Secret Provisioning

### Current State

The `setup.sh` script currently creates **placeholder secrets** and exits with an error code to warn that real credentials are needed. This is intentional — the stack should not silently start with fake credentials.

### Getting Real Secrets

Copy the Tailscale auth key from the shared secrets repo:

```bash
# If turnstone-stack-secrets is a sibling directory:
cp ../turnstone-stack-secrets/.ts_authkey ./secrets/ts_authkey 2>/dev/null || true

# Or decrypt and extract:
cd ../turnstone-stack-secrets
sops -d common/secrets.yaml | jq -r '.TS_AUTHKEY' > ../inference-stack/secrets/ts_authkey
```

The inference stack reads secrets directly from `turnstone-stack-secrets/secrets.yaml` via the SOPS entrypoint — no separate provisioning step is needed for service-specific secrets (HuggingFace token, ComfyUI password) as long as they exist in the shared secrets file.

### Required Secrets in `secrets.yaml`

The entrypoint script expects these keys to be present:

```yaml
TS_AUTHKEY: <tailscale machine auth key>   # For Tailscale container
HUGGING_FACE_HUB_TOKEN: <hf token>         # For SGLang (gated model access)
COMFYUI_PASSWORD: <web ui password>        # For ComfyUI login
```

## ROCm GPU Passthrough

### Verification

```bash
# Check device nodes exist
ls -la /dev/kfd /dev/dri/renderD128

# Check ROCm is available (if rocm-smi is installed)
rocm-smi
```

### HSA Override

Both services set `HSA_OVERRIDE_GFX_VERSION=12.0.0` to force compatibility with the R9700 GPU (gfx1201 architecture). This overrides ROCm's default hardware detection, which may not yet include native support for RDNA4 GPUs.

### Troubleshooting GPU Issues

- **Container fails to start** → Verify `/dev/kfd` and `/dev/dri/renderD128` are accessible from within WSL
- **OOM errors at inference time** → Model is too large for 32GB VRAM — use a smaller model or quantized variant
- **Slow inference despite GPU** → Check that `HSA_OVERRIDE_GFX_VERSION=12.0.0` is set and the container logs show ROCm device detection

## Data Persistence

| Directory | Purpose | Should be in git? |
|---|---|---|
| `tailscale_state/` | Tailscale auth state, WireGuard keys | ❌ (in .gitignore) |
| `comfyui/models/` | Checkpoints, LoRAs, VAEs | ❌ (can be many GB) |
| `comfyui/input/` | Input images for workflows | ❌ |
| `comfyui/output/` | Generated output images | ❌ |

Models and data directories grow large quickly. Consider using a separate data drive or symlinking to a larger partition if `/opt/data` has limited space.
