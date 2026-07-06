# Inference Stack Management (vLLM & ComfyUI)
.PHONY: setup up-vllm down-vllm up-comfy down-comfy status

setup:
	@echo "🚀 Setting up Inference Stack..."
	bash ./setup.sh

up-vllm:
	docker compose -f docker-compose.vllm.yml up -d

down-vllm:
	docker compose -f docker-compose.vllm.yml down

up-comfy:
	docker compose -f docker-compose.comfy.yml up -d

down-comfy:
	docker compose -f docker-compose.comfy.yml down

status:
	docker ps --filter "name=inference"
