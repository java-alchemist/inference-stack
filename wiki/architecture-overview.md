# Architecture Overview

## Purpose

The `inference-stack` repo is a **dedicated GPU inference layer** that runs alongside the main `turnstone-stack`. It provides high-throughput model serving (SGLang) and visual synthesis (ComfyUI) as separate, independently-manageable sessions.

### Why a Separate Repo?

1. **Isolation from core services** — Inference workloads are heavy and ephemeral. Keeping them in a separate compose stack prevents accidentally bringing down the entire AI OS when restarting GPU services.
2. **Alternative configurations** — This repo provides an SGLang-based LLM server (`docker-compose.sglang.yml`) as an alternative to the Lemonade server defined in `turnstone-stack/docker-compose-inference.yml`. You can experiment with different inference engines without modifying the core stack.
3. **Independent lifecycle** — Inference services have their own Tailscale identity, secrets provisioning, and data directories.

## Relationship to Turnstone Stack

```
┌───────────────────────┐          ┌──────────────────────────────┐
│   turnstone-stack     │          │      inference-stack         │
│                       │          │                              │
│  Tailscale (odin)     │◄──Tailnet►│  Tailscale (inference-*)    │
│  Turnstone Console    │          │  SGLang / ComfyUI           │
│  Hermes Gateway       │          │                              │
│  Ollama (LMS)         │          │  Shares secrets repo:        │
│  Open WebUI, Qdrant   │          │  turnstone-stack-secrets/    │
│  Synapse, SearXNG     │          └──────────────────────────────┘
│  ComfyUI / Lemonade   │
│  (alternative via      │
│   compose overlay)    │
└───────────────────────┘
```

Both stacks:
- Use the **same secrets repository** (`turnstone-stack-secrets`) for credential management
- Connect to the **same Tailscale tailnet** — services can communicate across stacks via MagicDNS
- Follow the **Zero-Visibility Secret Pattern** with SOPS + Age decryption at startup

## Compose File Strategy

Three compose files serve different purposes:

| File | Services | Use Case |
|---|---|---|
| `docker-compose.yml` | SGLang + ComfyUI (together) | Full inference stack — both services running simultaneously on a machine with sufficient VRAM |
| `docker-compose.sglang.yml` | SGLang only | LLM inference session only — for high-throughput text generation |
| `docker-compose.comfy.yml` | ComfyUI only | Image generation session only — frees VRAM from any LLM server |

Each file includes its own Tailscale sidecar container so the stack can operate independently.

## Session-Based GPU Architecture

The same principle as turnstone-stack: **launch one heavy service at a time**. Use `docker-compose.sglang.yml` or `docker-compose.comfy.yml` depending on what you need — not both simultaneously on a 32GB VRAM card.

```bash
# LLM inference session
make up-sglang     # Start SGLang + Tailscale

# Image generation session
make up-comfy      # Start ComfyUI + Tailscale

# Stop whichever is running
make down-sglang   # or make down-comfy
```
