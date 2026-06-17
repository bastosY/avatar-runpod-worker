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

# ── LoRA de REALISMO (URP) — camada barata, ANTES do hand-refiner (hf ainda intacto) ──
# Só aplicada quando o estilo for realista (env REALISM_LORA_NAME no backend). Trigger: "ultra-realistic portrait".
RUN HF=$(command -v hf || command -v huggingface-cli) && echo "HF CLI: $HF" && \
    "$HF" download prithivMLmods/Qwen-Image-Edit-2511-Ultra-Realistic-Portrait URP_15.safetensors --local-dir /tmp/urp && \
    mv /tmp/urp/URP_15.safetensors /comfyui/models/loras/qwen_realism_portrait.safetensors && \
    rm -rf /tmp/urp && \
    test -f /comfyui/models/loras/qwen_realism_portrait.safetensors

# ── hand refiner (ideia 1) — DEPOIS dos modelos p/ NÃO invalidar o cache de 25GB ──
# comfyui_controlnet_aux (MeshGraphormer-DepthMapPreprocessor) + deps + ckpts hr16
# + hand_yolov8s (reforço pro hand-detailer). Camada barata, isolada no fim.
# ⚠️ ORDEM IMPORTA: baixa com `hf` ANTES da requirements do controlnet_aux — ela rebaixa
# o huggingface_hub e o comando `hf` SOME (foi a causa do exit 127 no build anterior).
RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/Fannovel16/comfyui_controlnet_aux.git && \
    HF=$(command -v hf || command -v huggingface-cli) && echo "HF CLI: $HF" && \
    CK=/comfyui/custom_nodes/comfyui_controlnet_aux/ckpts/hr16/ControlNet-HandRefiner-pruned && \
    mkdir -p "$CK" && \
    "$HF" download hr16/ControlNet-HandRefiner-pruned graphormer_hand_state_dict.bin --local-dir "$CK" && \
    "$HF" download hr16/ControlNet-HandRefiner-pruned hrnetv2_w64_imagenet_pretrained.pth --local-dir "$CK" && \
    "$HF" download Bingsu/adetailer hand_yolov8s.pt --local-dir /comfyui/models/ultralytics/bbox && \
    test -f "$CK/graphormer_hand_state_dict.bin" && \
    test -f "$CK/hrnetv2_w64_imagenet_pretrained.pth" && \
    test -f /comfyui/models/ultralytics/bbox/hand_yolov8s.pt && \
    ([ -f comfyui_controlnet_aux/requirements.txt ] && python -m pip install --no-cache-dir -r comfyui_controlnet_aux/requirements.txt || true) && \
    python -m pip install --no-cache-dir mediapipe trimesh

# Sem CMD override: entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
