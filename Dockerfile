# Worker serverless ComfyUI + WAN/InfiniteTalk para RunPod.
# RunPod builda esta imagem direto do GitHub (Serverless → New Endpoint → GitHub).
# Os modelos NÃO ficam na imagem — são baixados no 1º start para o Network Volume
# montado em /runpod-volume (ver start.sh + download_models.sh).

FROM runpod/worker-comfyui:5.2.0-base

# ── custom nodes ────────────────────────────────────────────────────────────
# WanVideoWrapper (nós WanVideoModelLoader/MultiTalkModelLoader/etc.) + VideoHelperSuite
RUN comfy-node-install comfyui-wanvideowrapper comfyui-videohelpersuite || ( \
      cd /comfyui/custom_nodes && \
      git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
      git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
      pip install -r ComfyUI-WanVideoWrapper/requirements.txt && \
      pip install -r ComfyUI-VideoHelperSuite/requirements.txt \
    )

# dependências extras que o InfiniteTalk usa (wav2vec/áudio)
RUN pip install --no-cache-dir "huggingface_hub[cli]" librosa soundfile

# aponta o ComfyUI para os modelos no Network Volume
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY download_models.sh /download_models.sh
COPY start.sh /start_worker.sh
RUN chmod +x /download_models.sh /start_worker.sh

# nosso start: baixa modelos (idempotente) e then chama o entrypoint original do worker
CMD ["/start_worker.sh"]
