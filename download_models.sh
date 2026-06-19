#!/usr/bin/env bash
# Prefetch do modelo BASE Z-Image + adapter de de-distillation no HF cache (NO BUILD),
# p/ o ai-toolkit achar offline e NÃO baixar ~12GB a cada job de treino.
# branch: zimage-trainer
set -uo pipefail

HF=""
command -v hf >/dev/null 2>&1 && HF="hf"
[ -z "$HF" ] && command -v huggingface-cli >/dev/null 2>&1 && HF="huggingface-cli"
if [ -z "$HF" ]; then echo "✗ FATAL: nenhum CLI do huggingface (hf/huggingface-cli)"; exit 1; fi
echo "=== prefetch Z-Image base + training adapter ($HF) ==="

BASE="${ZIMAGE_BASE_MODEL:-Tongyi-MAI/Z-Image-Turbo}"
ADAPTER="${ZIMAGE_TRAIN_ADAPTER:-ostris/zimage_turbo_training_adapterV2}"

# base (OBRIGATÓRIO — falha o build se não baixar; senão a imagem fica inútil)
echo "↓ base: $BASE"
$HF download "$BASE" || { echo "✗ FATAL: base model $BASE"; exit 1; }

# adapter de de-distillation (best-effort: o ai-toolkit busca em runtime se faltar).
# Evita "turbo drift": carregado SÓ no treino; a LoRA final roda no modelo distilado normal.
echo "↓ adapter: $ADAPTER"
$HF download "$ADAPTER" || echo "⚠ adapter não prefetchado (ai-toolkit busca em runtime)"

echo "✓ prefetch ok"
