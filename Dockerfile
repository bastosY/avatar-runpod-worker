# Worker serverless ComfyUI + WAN/InfiniteTalk para RunPod.
# RunPod builda esta imagem direto do GitHub (Serverless → New Endpoint → GitHub).
# Os modelos NÃO ficam na imagem — são baixados no 1º start para o Network Volume
# montado em /runpod-volume (ver start.sh + download_models.sh).

FROM runpod/worker-comfyui:5.2.0-base

# ── atualiza o ComfyUI core ─────────────────────────────────────────────────
# A base 5.2.0 traz um ComfyUI antigo demais p/ o WanVideoWrapper atual
# (faltava comfy.ldm.flux.math.apply_rope1). Atualiza para o master recente.
RUN git config --global --add safe.directory /comfyui && \
    cd /comfyui && git fetch --depth 1 origin master && git reset --hard FETCH_HEAD && \
    python -m pip install --no-cache-dir -r requirements.txt

# ── custom nodes ────────────────────────────────────────────────────────────
# WanVideoWrapper (nós WanVideoModelLoader/MultiTalkModelLoader/etc.) + VideoHelperSuite.
# Usa o MESMO python do ComfyUI (python -m pip) para as deps caírem no env certo.
RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    python -m pip install --no-cache-dir -r ComfyUI-WanVideoWrapper/requirements.txt && \
    python -m pip install --no-cache-dir -r ComfyUI-VideoHelperSuite/requirements.txt

# ── diagnóstico (aparece no BUILD LOG) ──────────────────────────────────────
# mostra o ambiente e carrega todos os nodes; se o WanVideoWrapper falhar ao
# importar, o traceback/erro fica visível aqui no log do build.
RUN echo "=== PYTHON ===" && which python && python --version && \
    echo "=== custom_nodes ===" && ls /comfyui/custom_nodes && \
    echo "=== NODE LOAD TEST ===" && cd /comfyui && \
    (timeout 300 python main.py --quick-test-for-ci --cpu 2>&1 | \
       grep -iE "wanvideo|videohelper|import times|fail|error|traceback|no module" | head -50 || true)

# dependências extras que o InfiniteTalk usa (wav2vec/áudio)
RUN pip install --no-cache-dir "huggingface_hub[cli]" librosa soundfile

# aponta o ComfyUI para os modelos no Network Volume
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY download_models.sh /download_models.sh
COPY start.sh /start_worker.sh
RUN chmod +x /download_models.sh /start_worker.sh

# nosso start: baixa modelos (idempotente) e then chama o entrypoint original do worker
CMD ["/start_worker.sh"]
