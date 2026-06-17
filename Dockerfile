# Worker serverless ComfyUI — geração de IMAGEM (Qwen-Image-Edit 2511, 4-step).
# Substitui o Nano Banana Pro: edição/consistência de personagem a partir de refs,
# custo ~zero por imagem (só GPU). Modelos ASSADOS na imagem (sem volume).
# branch: image — endpoint de IMAGEM separado do de vídeo.

FROM runpod/worker-comfyui:5.2.0-base

# ── compilador C p/ o triton (GPUs Blackwell JIT-compilam kernels fp8) ───────
ENV CC=gcc
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

# ── atualiza o ComfyUI core ─────────────────────────────────────────────────
# Os nodes do Qwen-Image-Edit (TextEncodeQwenImageEditPlus etc.) são NATIVOS do
# ComfyUI recente — a base 5.2.0 é antiga demais. Atualiza para o master.
RUN git config --global --add safe.directory /comfyui && \
    cd /comfyui && git fetch --depth 1 origin master && git reset --hard FETCH_HEAD && \
    python -m pip install --no-cache-dir -r requirements.txt

# Qwen usa só nodes nativos → NÃO precisa do WanVideoWrapper (worker mais leve).
RUN python -m pip install --no-cache-dir "huggingface_hub[cli]"

# ── modelos ASSADOS na imagem (no build) ────────────────────────────────────
# ~25GB (diffusion 4-step merged + text encoder + vae). Camada cara ANTES das
# baratas (boto3/handler) p/ o cache ser reaproveitado em rebuilds.
COPY download_models.sh /download_models.sh
RUN chmod +x /download_models.sh && MODELS_DIR=/comfyui/models /download_models.sh

# ── camadas baratas no FINAL ────────────────────────────────────────────────
RUN python -m pip install --no-cache-dir boto3

# handler patchado: sobe a saída (SaveImage → "images") pro R2/S3 quando as env
# vars BUCKET_* estão setadas (mesmo handler do worker de vídeo).
COPY handler.py /handler.py

# ── LoRA de REALISMO (URP) — camada barata no fim (não invalida os 25GB) ──────
# Anti-plástico. Aplicada só quando o estilo for realista (trigger "ultra-realistic portrait").
# Usa `hf` OU `huggingface-cli` (o `hf` pode não existir dependendo da versão do huggingface_hub).
RUN HF=$(command -v hf || command -v huggingface-cli) && echo "HF CLI: $HF" && \
    "$HF" download prithivMLmods/Qwen-Image-Edit-2511-Ultra-Realistic-Portrait URP_15.safetensors --local-dir /tmp/urp && \
    mv /tmp/urp/URP_15.safetensors /comfyui/models/loras/qwen_realism_portrait.safetensors && \
    rm -rf /tmp/urp && \
    test -f /comfyui/models/loras/qwen_realism_portrait.safetensors

# Sem CMD override: entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
