# Worker serverless ComfyUI + WAN/InfiniteTalk (720p) — modelos ASSADOS na imagem.
# Sem Network Volume: a imagem é autossuficiente, então o endpoint roda em QUALQUER
# região com GPU (sem travar numa zona). RunPod builda esta imagem direto do GitHub.

FROM runpod/worker-comfyui:5.2.0-base

# ── compilador C p/ o triton ────────────────────────────────────────────────
# GPUs novas (Blackwell/5090) precisam que o triton JIT-compile os kernels fp8;
# sem gcc o ComfyUI crasha ("Failed to find C compiler"). Sageattention p/ acelerar.
ENV CC=gcc
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

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
# IMPORTANTE: esta camada (a cara) fica ANTES das camadas que mudam toda hora
# (boto3 + handler), pra o cache dos 40GB ser reaproveitado em rebuilds.
COPY download_models.sh /download_models.sh
RUN chmod +x /download_models.sh && MODELS_DIR=/comfyui/models /download_models.sh

# ── camadas baratas no FINAL (mudam com frequência → rebuild em segundos) ────
RUN python -m pip install --no-cache-dir boto3

# ── SageAttention: acelera a atenção (attention_mode="sageattn" no WanVideoModelLoader) ─
# v1 é triton puro (sem compilar kernels CUDA), instala via pip. gcc já está acima p/ o triton JIT.
# No FINAL p/ não invalidar o cache dos 40GB de modelos.
RUN python -m pip install --no-cache-dir sageattention

# handler patchado: o handler do worker-comfyui 5.2.0 SÓ trata a key "images" e
# ignora "gifs" (vídeo do VHS_VideoCombine) → retornava success_no_images. Este
# patch sobe o mp4 pro R2/S3 (boto3 explícito, bucket vindo do BUCKET_ENDPOINT_URL).
COPY handler.py /handler.py

# Sem CMD override: o entrypoint padrão do worker-comfyui inicia ComfyUI + handler.
# ComfyUI acha os modelos nativamente em /comfyui/models (sem extra_model_paths).
