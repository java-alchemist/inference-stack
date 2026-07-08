# Inference Stack Management (SGLang & ComfyUI)
.PHONY: setup up-sglang down-sglang up-comfy down-comfy status

setup:
	@echo "🚀 Setting up Inference Stack..."
	bash ./setup.sh

up-sglang:
	docker compose -f docker-compose.sglang.yml up -d

down-sglang:
	docker compose -f docker-compose.sglang.yml down

up-comfy:
	docker compose -f docker-compose.comfy.yml up -d

down-comfy:
	docker compose -f docker-compose.comfy.yml down

status:
	docker ps --filter "name=inference"
