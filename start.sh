#!/usr/bin/env bash
# Start do worker: baixa os modelos (idempotente), LINKA o volume dentro de
# /comfyui/models (evita depender do extra_model_paths) e entrega pro entrypoint
# original do runpod/worker-comfyui.
set -uo pipefail

if [ -d /runpod-volume ]; then
  echo "→ baixando modelos para o volume…"
  /download_models.sh

  echo "→ linkando /runpod-volume/models -> /comfyui/models …"
  for d in diffusion_models text_encoders vae clip_vision loras; do
    mkdir -p "/runpod-volume/models/$d"
    rm -rf "/comfyui/models/$d"
    ln -s "/runpod-volume/models/$d" "/comfyui/models/$d"
  done

  echo "=== O QUE O COMFYUI VAI VER ==="
  for d in diffusion_models text_encoders vae clip_vision loras; do
    echo "-- $d --"; ls -la "/comfyui/models/$d/" 2>/dev/null
  done
else
  echo "⚠ /runpod-volume NÃO montado — anexe o Network Volume ao endpoint."
fi

# entrypoint original do worker-comfyui (inicia ComfyUI + handler do RunPod)
exec /start.sh
