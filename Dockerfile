# Worker serverless ComfyUI — CHARACTER SHEET (Qwen-Image-Edit 2511).
# Método "Mickmumpitz-no-Qwen": pose-grid via ControlNet + crop, expressões via
# LivePortrait, FaceDetailer + UltimateSDUpscale. Tudo no Qwen (sem Flux).
# branch: charsheet — endpoint serverless SEPARADO (mais pesado que o `image`).
#
# ⚠️ Build pesado e arriscado: 4 custom nodes + insightface (compila) + ~6 modelos.
# Ordem de depuração se falhar: (1) custom nodes/pip, (2) insightface, (3) modelos.

FROM runpod/worker-comfyui:5.2.0-base

# ── compilador C (triton fp8 + insightface compila C/C++) ────────────────────
ENV CC=gcc
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake && \
    rm -rf /var/lib/apt/lists/*

# ── ComfyUI core atualizado (nodes nativos do Qwen + ControlNetApplySD3) ─────
RUN git config --global --add safe.directory /comfyui && \
    cd /comfyui && git fetch --depth 1 origin master && git reset --hard FETCH_HEAD && \
    python -m pip install --no-cache-dir -r requirements.txt

RUN python -m pip install --no-cache-dir "huggingface_hub[cli]"

# ── custom nodes ─────────────────────────────────────────────────────────────
# Impact-Pack (FaceDetailer) + Impact-Subpack (UltralyticsDetectorProvider),
# UltimateSDUpscale, AdvancedLivePortrait (ExpressionEditor → expressões via warp).
RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git && \
    git clone --depth 1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git && \
    git clone --depth 1 https://github.com/PowerHouseMan/ComfyUI-AdvancedLivePortrait.git && \
    for d in ComfyUI-Impact-Pack ComfyUI-Impact-Subpack ComfyUI_UltimateSDUpscale ComfyUI-AdvancedLivePortrait; do \
      [ -f "$d/requirements.txt" ] && python -m pip install --no-cache-dir -r "$d/requirements.txt" || true; \
    done

# insightface + onnxruntime: LivePortrait precisa (detecção/landmark de rosto).
RUN python -m pip install --no-cache-dir insightface onnxruntime

# ── modelos ASSADOS (no build) ───────────────────────────────────────────────
# Qwen (25GB) + camera LoRA + ControlNet-Union + upscaler + yolov8 + LivePortrait.
# Camada cara ANTES das baratas (boto3/handler) p/ reaproveitar cache.
COPY download_models.sh /download_models.sh
RUN chmod +x /download_models.sh && MODELS_DIR=/comfyui/models /download_models.sh

# ── camadas baratas no FINAL ────────────────────────────────────────────────
RUN python -m pip install --no-cache-dir boto3
COPY handler.py /handler.py

# Sem CMD override: entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
