# =============================================================================
# AI-Local-Sandbox Makefile
# Manages: venv, dependencies, app launch, GGUF extras, lint, clean, etc.
# =============================================================================

SHELL      := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Paths & config
# ---------------------------------------------------------------------------
# Auto-detect venv: prefer VIRTUAL_ENV if activated, then local .venv, then ~/. venv
ifdef VIRTUAL_ENV
  VENV_DIR := $(VIRTUAL_ENV)
else ifneq (,$(wildcard .venv/bin/python))
  VENV_DIR := .venv
else ifneq (,$(wildcard $(HOME)/.venv/bin/python))
  VENV_DIR := $(HOME)/.venv
else
  VENV_DIR := .venv
endif

PYTHON     := $(VENV_DIR)/bin/python
PIP        := $(VENV_DIR)/bin/pip
PORT       := 7860

PIPER_DIR  := $(HOME)/piper_voices/libritts_r_medium
PIPER_ONNX := $(PIPER_DIR)/en_US-libritts_r-medium.onnx
PIPER_JSON := $(PIPER_DIR)/en_US-libritts_r-medium.onnx.json

# PyTorch CUDA wheel index (change cu121 → cu124 etc. if needed)
TORCH_INDEX := https://download.pytorch.org/whl/cu121

# ---------------------------------------------------------------------------
# Colour helpers (non-critical, degrade gracefully)
# ---------------------------------------------------------------------------
_CYAN  := \033[36m
_GREEN := \033[32m
_YELLOW:= \033[33m
_RED   := \033[31m
_RESET := \033[0m

# =============================================================================
# HELP
# =============================================================================
.PHONY: help
help: ## Show this help
	@echo ""
	@echo -e "$(_CYAN)AI-Local-Sandbox$(_RESET)  —  available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(_GREEN)%-22s$(_RESET) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================
.PHONY: venv
venv: $(VENV_DIR)/bin/activate ## Create Python venv (if not exists)

$(VENV_DIR)/bin/activate:
	@echo -e "$(_CYAN)[SETUP]$(_RESET) Creating Python venv in $(VENV_DIR) ..."
	python3 -m venv $(VENV_DIR)
	$(PIP) install --upgrade pip setuptools wheel
	@echo -e "$(_GREEN)[SETUP]$(_RESET) venv ready."

.PHONY: install-torch
install-torch: venv ## Install PyTorch + CUDA wheels
	@echo -e "$(_CYAN)[DEPS]$(_RESET) Installing PyTorch (CUDA) from $(TORCH_INDEX) ..."
	$(PIP) install torch torchvision torchaudio --index-url $(TORCH_INDEX)
	@echo -e "$(_GREEN)[DEPS]$(_RESET) PyTorch installed."

.PHONY: install
install: venv ## Install all project dependencies (requirements.txt)
	@echo -e "$(_CYAN)[DEPS]$(_RESET) Installing requirements.txt ..."
	$(PIP) install -r requirements.txt
	@echo -e "$(_GREEN)[DEPS]$(_RESET) Done."

.PHONY: install-lock
install-lock: venv ## Install pinned dependencies (requirements.lock.txt)
	@echo -e "$(_CYAN)[DEPS]$(_RESET) Installing requirements.lock.txt (pinned) ..."
	$(PIP) install -r requirements.lock.txt
	@echo -e "$(_GREEN)[DEPS]$(_RESET) Done (locked versions)."

.PHONY: install-gguf
install-gguf: venv ## Install llama-cpp-python prebuilt CUDA wheel (recommended)
	@echo -e "$(_CYAN)[DEPS]$(_RESET) Installing prebuilt llama-cpp-python wheel (cu124) ..."
	$(PIP) install --timeout 600 llama-cpp-python \
		--extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124
	$(PIP) install huggingface_hub
	@echo -e "$(_GREEN)[DEPS]$(_RESET) GGUF dependencies ready."

.PHONY: install-gguf-build
install-gguf-build: venv ## Install llama-cpp-python from source (needs nvcc, see docs/err-install.md)
	@command -v nvcc >/dev/null 2>&1 || { \
		echo -e "$(_RED)[ERROR]$(_RESET) nvcc not found. Install CUDA Toolkit first:"; \
		echo -e "         $(_YELLOW)make install-cuda-toolkit$(_RESET)"; \
		echo -e "         See docs/err-install.md for known issues."; \
		exit 1; \
	}
	@echo -e "$(_CYAN)[DEPS]$(_RESET) Building llama-cpp-python from source with CUDA ..."
	CMAKE_ARGS="-DGGML_CUDA=on" $(PIP) install llama-cpp-python --no-binary llama-cpp-python
	$(PIP) install huggingface_hub
	@echo -e "$(_GREEN)[DEPS]$(_RESET) GGUF dependencies ready (source build)."

.PHONY: install-gguf-cpu
install-gguf-cpu: venv ## Install llama-cpp-python (CPU-only) for GGUF mode
	@echo -e "$(_CYAN)[DEPS]$(_RESET) Installing llama-cpp-python (CPU-only) ..."
	$(PIP) install llama-cpp-python
	$(PIP) install huggingface_hub
	@echo -e "$(_GREEN)[DEPS]$(_RESET) GGUF dependencies ready (CPU)."

.PHONY: install-cuda-toolkit
install-cuda-toolkit: ## Install CUDA Toolkit (nvcc) — requires sudo
	@echo -e "$(_CYAN)[SYS]$(_RESET) Installing nvidia-cuda-toolkit (this may take a while) ..."
	sudo apt update && sudo apt install -y nvidia-cuda-toolkit
	@nvcc --version
	@echo -e "$(_GREEN)[SYS]$(_RESET) CUDA Toolkit installed. Now run: make install-gguf"

.PHONY: install-all
install-all: install-system install-torch install install-gguf install-piper-voice ## Full setup: system + PyTorch + deps + GGUF wheel + Piper voice

.PHONY: install-system
install-system: ## Install system-level packages (ffmpeg, etc.) — requires sudo
	@echo -e "$(_CYAN)[SYS]$(_RESET) Installing system packages ..."
	sudo apt update && sudo apt install -y ffmpeg python3-venv
	@echo -e "$(_GREEN)[SYS]$(_RESET) System packages installed."

.PHONY: install-piper-voice
install-piper-voice: ## Download default Piper TTS voice model
	@echo -e "$(_CYAN)[TTS]$(_RESET) Downloading Piper voice to $(PIPER_DIR) ..."
	mkdir -p $(PIPER_DIR)
	wget -q --show-progress -O $(PIPER_ONNX) \
		https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx
	wget -q --show-progress -O $(PIPER_JSON) \
		https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx.json
	@echo -e "$(_GREEN)[TTS]$(_RESET) Piper voice ready."

.PHONY: freeze
freeze: venv ## Regenerate requirements.lock.txt from current venv
	@echo -e "$(_CYAN)[LOCK]$(_RESET) Freezing pip packages ..."
	$(PIP) freeze > requirements.lock.txt
	@echo -e "$(_GREEN)[LOCK]$(_RESET) requirements.lock.txt updated."

# =============================================================================
# RUN APPLICATIONS
# =============================================================================
.PHONY: run
run: venv ## Run MiniCPM chat (HuggingFace AutoModel, default)
	@echo -e "$(_CYAN)[RUN]$(_RESET) Starting minicpm.py on port $(PORT) ..."
	$(PYTHON) minicpm.py

.PHONY: run-gguf
run-gguf: venv ## Run MiniCPM-o GGUF chat (llama-cpp-python, Q4_K_M)
	@echo -e "$(_CYAN)[RUN]$(_RESET) Starting minicpm-o.py (GGUF) on port $(PORT) ..."
	$(PYTHON) minicpm-o.py

.PHONY: run-webcam
run-webcam: venv ## Run webcam live streaming
	@echo -e "$(_CYAN)[RUN]$(_RESET) Starting webcam_live_gradio.py ..."
	$(PYTHON) webcam_live_gradio.py

.PHONY: run-sdxl
run-sdxl: venv ## Run SDXL image generation (custom)
	@echo -e "$(_CYAN)[RUN]$(_RESET) Starting sdxl.py on port $(PORT) ..."
	$(PYTHON) sdxl.py

.PHONY: run-sdxl-safe
run-sdxl-safe: venv ## Run SDXL image generation (safe mode)
	@echo -e "$(_CYAN)[RUN]$(_RESET) Starting sdxl_safe.py on port $(PORT) ..."
	$(PYTHON) sdxl_safe.py

.PHONY: run-sdxl-canny
run-sdxl-canny: venv ## Run SDXL image generation (ControlNet Canny)
	@echo -e "$(_CYAN)[RUN]$(_RESET) Starting sdxl_safe_canny.py on port $(PORT) ..."
	$(PYTHON) sdxl_safe_canny.py

# =============================================================================
# VALIDATION & LINT
# =============================================================================
.PHONY: lint
lint: ## Syntax-check all Python files (ast.parse)
	@echo -e "$(_CYAN)[LINT]$(_RESET) Checking Python syntax ..."
	@fail=0; \
	for f in *.py; do \
		$(PYTHON) -c "import ast; ast.parse(open('$$f').read())" 2>/dev/null \
			&& echo -e "  $(_GREEN)OK$(_RESET)  $$f" \
			|| { echo -e "  $(_RED)FAIL$(_RESET) $$f"; fail=1; }; \
	done; \
	[ $$fail -eq 0 ] && echo -e "$(_GREEN)[LINT]$(_RESET) All files OK." || exit 1

.PHONY: check-deps
check-deps: venv ## Verify critical imports are available
	@echo -e "$(_CYAN)[CHECK]$(_RESET) Verifying key packages ..."
	@$(PYTHON) -c "import torch; print(f'  torch {torch.__version__}  CUDA={torch.cuda.is_available()}')"
	@$(PYTHON) -c "import transformers; print(f'  transformers {transformers.__version__}')" 2>/dev/null || echo "  transformers: NOT INSTALLED"
	@$(PYTHON) -c "import gradio; print(f'  gradio {gradio.__version__}')" 2>/dev/null || echo "  gradio: NOT INSTALLED"
	@$(PYTHON) -c "import diffusers; print(f'  diffusers {diffusers.__version__}')" 2>/dev/null || echo "  diffusers: NOT INSTALLED"
	@$(PYTHON) -c "import faster_whisper; print(f'  faster_whisper OK')" 2>/dev/null || echo "  faster_whisper: NOT INSTALLED"
	@$(PYTHON) -c "import llama_cpp; print(f'  llama_cpp OK')" 2>/dev/null || echo "  llama_cpp: NOT INSTALLED (run: make install-gguf)"
	@$(PYTHON) -c "import huggingface_hub; print(f'  huggingface_hub {huggingface_hub.__version__}')" 2>/dev/null || echo "  huggingface_hub: NOT INSTALLED"
	@echo -e "$(_GREEN)[CHECK]$(_RESET) Done."

.PHONY: check-gpu
check-gpu: venv ## Print GPU info (CUDA devices, VRAM)
	@$(PYTHON) -c "\
import torch; \
n = torch.cuda.device_count(); \
print(f'CUDA devices: {n}'); \
[print(f'  [{i}] {torch.cuda.get_device_name(i)}  VRAM={torch.cuda.get_device_properties(i).total_memory/(1<<30):.1f}GB') for i in range(n)]" 2>/dev/null \
		|| echo "No CUDA devices found."

# =============================================================================
# CLEAN
# =============================================================================
.PHONY: clean
clean: ## Remove Python caches and temp files
	@echo -e "$(_CYAN)[CLEAN]$(_RESET) Removing caches ..."
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name '*.pyc' -delete 2>/dev/null || true
	find /tmp -maxdepth 1 -name 'minicpm_tts_*' -delete 2>/dev/null || true
	find /tmp -maxdepth 1 -name 'tts_*' -delete 2>/dev/null || true
	@echo -e "$(_GREEN)[CLEAN]$(_RESET) Done."

.PHONY: clean-venv
clean-venv: ## Remove the entire venv directory
	@echo -e "$(_YELLOW)[CLEAN]$(_RESET) Removing $(VENV_DIR) ..."
	rm -rf $(VENV_DIR)
	@echo -e "$(_GREEN)[CLEAN]$(_RESET) venv removed."

.PHONY: clean-hf-cache
clean-hf-cache: ## Remove HuggingFace model cache (~/.cache/huggingface)
	@echo -e "$(_YELLOW)[CLEAN]$(_RESET) Removing HuggingFace cache (this will re-download models) ..."
	rm -rf $(HOME)/.cache/huggingface/hub
	@echo -e "$(_GREEN)[CLEAN]$(_RESET) HF cache removed."

.PHONY: clean-all
clean-all: clean clean-venv ## Full cleanup: caches + venv (does NOT delete HF model cache)
	@echo -e "$(_GREEN)[CLEAN]$(_RESET) All cleaned."

.PHONY: kill
kill: ## Kill any Gradio processes on port $(PORT)
	@echo -e "$(_YELLOW)[KILL]$(_RESET) Stopping processes on port $(PORT) ..."
	@lsof -ti :$(PORT) | xargs -r kill -9 2>/dev/null && \
		echo -e "$(_GREEN)[KILL]$(_RESET) Killed." || \
		echo -e "$(_GREEN)[KILL]$(_RESET) No process on port $(PORT)."
