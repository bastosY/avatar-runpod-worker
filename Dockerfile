# Worker serverless ComfyUI + WAN/InfiniteTalk (720p) — modelos ASSADOS na imagem.
# Sem Network Volume: a imagem é autossuficiente, então o endpoint roda em QUALQUER
# região com GPU (sem travar numa zona). RunPod builda esta imagem direto do GitHub.

FROM runpod/worker-comfyui:5.2.0-base

# ── atualiza o ComfyUI core ─────────────────────────────────────────────────
# A base 5.2.0 traz um ComfyUI antigo demais p/ o WanVideoWrapper atual
# (faltava comfy.ldm.flux.math.apply_rope1). Atualiza para o master recente.
RUN git config --global --add safe.directory /comfyui && \
    cd /comfyui && git fetch --depth 1 origin master && git reset --hard FETCH_HEAD && \
    python -m pip install --no-cache-dir -r requirements.txt

# ── custom nodes ────────────────────────────────────────────────────────────
RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    python -m pip install --no-cache-dir -r ComfyUI-WanVideoWrapper/requirements.txt && \
    python -m pip install --no-cache-dir -r ComfyUI-KJNodes/requirements.txt && \
    python -m pip install --no-cache-dir -r ComfyUI-VideoHelperSuite/requirements.txt

RUN python -m pip install --no-cache-dir "huggingface_hub[cli]" librosa soundfile

# ── modelos ASSADOS na imagem (no build) ────────────────────────────────────
# ~40GB baixados aqui → imagem autossuficiente, sem volume, sem download em runtime.
COPY download_models.sh /download_models.sh
RUN chmod +x /download_models.sh && MODELS_DIR=/comfyui/models /download_models.sh

# Sem CMD override: o entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
# ComfyUI acha os modelos nativamente em /comfyui/models (sem extra_model_paths).
