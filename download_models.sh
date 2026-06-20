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
# o "adapter" é um ARQUIVO dentro do repo (v1/v2). O ai-toolkit quer o CAMINHO do arquivo,
# não o repo id → assamos o v2 em /adapters e apontamos o caminho local no handler.
ADAPTER_REPO="${ZIMAGE_TRAIN_ADAPTER_REPO:-ostris/zimage_turbo_training_adapter}"
ADAPTER_FILE="${ZIMAGE_TRAIN_ADAPTER_FILE:-zimage_turbo_training_adapter_v2.safetensors}"

# base (OBRIGATÓRIO — falha o build se não baixar; senão a imagem fica inútil)
echo "↓ base: $BASE"
$HF download "$BASE" || { echo "✗ FATAL: base model $BASE"; exit 1; }

# adapter de de-distillation (OBRIGATÓRIO agora — o arquivo específico, assado em /adapters).
mkdir -p /adapters
echo "↓ adapter: $ADAPTER_REPO :: $ADAPTER_FILE"
tmp=$(mktemp -d)
if $HF download "$ADAPTER_REPO" "$ADAPTER_FILE" --local-dir "$tmp" && [ -f "$tmp/$ADAPTER_FILE" ]; then
  mv "$tmp/$ADAPTER_FILE" "/adapters/$ADAPTER_FILE" && echo "  ✓ adapter assado: /adapters/$ADAPTER_FILE"
else
  echo "✗ FATAL: adapter $ADAPTER_REPO :: $ADAPTER_FILE"; rm -rf "$tmp"; exit 1
fi
rm -rf "$tmp"

echo "✓ prefetch ok"
