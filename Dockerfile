# Worker serverless ComfyUI — Z-Image Turbo + LoRA de PERSONAGEM (TEXT-TO-IMAGE).
# Identidade do personagem vem de uma LoRA Z-Image (treinada do charsheet), BAIXADA EM RUNTIME
# do R2 (sem rebuild por personagem). Cena/roupa no prompt. Apache 2.0 → comercial OK.
# Modelos base ASSADOS na imagem (sem Network Volume → roda em qualquer datacenter).
# branch: zimage

FROM runpod/worker-comfyui:5.2.0-base

# ── compilador C (triton JIT em GPUs novas) + git p/ clonar custom node ──────
ENV CC=gcc
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git && \
    rm -rf /var/lib/apt/lists/*

# ── atualiza o ComfyUI core ─────────────────────────────────────────────────
# Os nodes do Z-Image (arquitetura Lumina2) são NATIVOS do ComfyUI recente — a base
# 5.2.0 é antiga demais. Atualiza para o master.
RUN git config --global --add safe.directory /comfyui && \
    cd /comfyui && git fetch --depth 1 origin master && git reset --hard FETCH_HEAD && \
    python -m pip install --no-cache-dir -r requirements.txt

RUN python -m pip install --no-cache-dir "huggingface_hub[cli]"

# ── custom node: Z-Image Turbo LoRA Loader (capitan01R) ──────────────────────
# CRÍTICO: o LoraLoader genérico do ComfyUI DROPA SILENCIOSAMENTE a atenção em Z-Image
# (QKV fundido) → a LoRA "carrega" mas a identidade não transfere. Este loader funde
# Q/K/V no formato nativo (auto_convert_qkv) e remapeia as chaves. Sem ele, a LoRA é inútil.
RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/capitan01R/Comfyui-ZiT-Lora-loader.git && \
    if [ -f Comfyui-ZiT-Lora-loader/requirements.txt ]; then \
      python -m pip install --no-cache-dir -r Comfyui-ZiT-Lora-loader/requirements.txt; \
    fi

# ── modelos base ASSADOS na imagem (no build) ───────────────────────────────
# ~20GB (Z-Image Turbo bf16 + text encoder Qwen3-4B + vae). Camada cara ANTES das
# baratas (boto3/handler) p/ reaproveitar cache em rebuilds. loras/ fica VAZIA (R2 runtime).
COPY download_models.sh /download_models.sh
RUN chmod +x /download_models.sh && MODELS_DIR=/comfyui/models /download_models.sh

# ── camadas baratas no FINAL ────────────────────────────────────────────────
RUN python -m pip install --no-cache-dir boto3

# handler patchado: (1) baixa LoRA do personagem do R2 p/ models/loras antes de rodar
# (cache em disco, on-demand); (2) sobe a saída (SaveImage) pro R2/S3 com BUCKET_* setadas.
COPY handler.py /handler.py

# Sem CMD override: entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
