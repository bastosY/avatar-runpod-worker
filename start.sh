#!/usr/bin/env bash
# Start do worker: baixa os modelos (idempotente) e entrega pro entrypoint original
# do runpod/worker-comfyui. O download só acontece de fato no 1º cold start.
set -euo pipefail

if [ -d /runpod-volume ]; then
  echo "→ verificando modelos no Network Volume…"
  /download_models.sh || echo "⚠ download falhou (worker segue; verifique paths/HF)."
else
  echo "⚠ /runpod-volume não montado — anexe um Network Volume ao endpoint."
fi

# entrypoint original do worker-comfyui (inicia ComfyUI + handler do RunPod)
exec /start.sh
