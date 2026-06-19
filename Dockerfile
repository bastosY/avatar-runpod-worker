# Worker serverless de TREINO — LoRA de personagem Z-Image (Ostris ai-toolkit).
# Recebe dataset (charsheet) + config → treina → sobe loras/<slug>.safetensors no R2.
# 1 POST = 1 personagem treinado. Roda em 4090 (24GB). branch: zimage-trainer
#
# Separado do worker de INFERÊNCIA (branch zimage): treino é job longo (~10-30min) e tem
# deps diferentes (ai-toolkit, não ComfyUI). Ambos cospem o mesmo .safetensors no R2.

FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel

ENV DEBIAN_FRONTEND=noninteractive \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      git build-essential ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# ── Ostris ai-toolkit (treinador de LoRA; suporta Z-Image Turbo) ─────────────
RUN git clone --depth 1 https://github.com/ostris/ai-toolkit /ai-toolkit && \
    cd /ai-toolkit && git submodule update --init --recursive && \
    pip install -r requirements.txt

# deps do worker (runpod handler + R2 + render do yaml + hf)
RUN pip install runpod boto3 pyyaml "huggingface_hub[cli]" hf_transfer

# ── prefetch base + adapter no HF cache (camada cara ANTES do handler) ───────
COPY download_models.sh /download_models.sh
RUN chmod +x /download_models.sh && /download_models.sh

# handler de treino (serverless): dataset → config.yaml → ai-toolkit → R2
COPY handler.py /handler.py
CMD ["python", "-u", "/handler.py"]
