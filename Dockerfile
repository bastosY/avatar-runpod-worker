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

# ── perf: tirar o offload de pesos pra CPU ──────────────────────────────────
# Log do worker mostrou "Set vram state to: NORMAL_VRAM" + "async weight offloading" + text
# encoder "current: cpu" — mesmo com 80GB livres no H100, estava fazendo streaming CPU↔GPU.
# A base hard-coda os args do ComfyUI (sem env/arquivo) → injeta --highvram direto no launch.
# Mantém modelo+encoders residentes na GPU. Falha o build se o start.sh mudar de padrão.
RUN test -f /start.sh && sed -i 's/--disable-metadata/--disable-metadata --highvram/' /start.sh && \
    grep -q -- '--highvram' /start.sh && echo "✓ --highvram injetado no start.sh" || \
    { echo "✗ start.sh não encontrado ou padrão mudou — revisar"; exit 1; }

# ── camadas baratas no FINAL ────────────────────────────────────────────────
RUN python -m pip install --no-cache-dir boto3

# handler patchado: sobe a saída (SaveImage → "images") pro R2/S3 quando as env
# vars BUCKET_* estão setadas (mesmo handler do worker de vídeo).
COPY handler.py /handler.py

# Sem CMD override: entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
