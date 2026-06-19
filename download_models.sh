#!/usr/bin/env bash
# Baixa o Z-Image Turbo (TEXT-TO-IMAGE) p/ o ComfyUI. Roda NO BUILD (assa na imagem) ~20GB.
# Worker de geração com LoRA de PERSONAGEM: identidade nas weights da LoRA (baixada em runtime
# do R2), cena/roupa no prompt. Apache 2.0 (Tongyi-MAI) → comercial liberado.
# IMPORTANTE: FALHA o build se algum arquivo não baixar (não deixa imagem sem modelo).
set -uo pipefail

VOL="${MODELS_DIR:-/comfyui/models}"
mkdir -p "$VOL"/{diffusion_models,text_encoders,vae,loras}
echo "=== baixando Z-Image Turbo para $VOL ==="

# CLI do huggingface_hub: 'hf' (novo) ou 'huggingface-cli' (antigo).
HF=""
command -v hf >/dev/null 2>&1 && HF="hf"
[ -z "$HF" ] && command -v huggingface-cli >/dev/null 2>&1 && HF="huggingface-cli"
if [ -z "$HF" ]; then echo "✗ FATAL: nenhum CLI do huggingface (hf/huggingface-cli) encontrado"; exit 1; fi
echo "HF CLI: $HF"

dl() { # repo  path-no-repo  pasta-destino  nome-de-saida
  local repo="$1" path="$2" dest="$3" out="$4"
  local final="$VOL/$dest/$out"
  if [ -f "$final" ]; then echo "✓ já existe: $out"; return 0; fi
  echo "↓ $out  ($repo :: $path)"
  local tmp; tmp=$(mktemp -d)
  if $HF download "$repo" "$path" --local-dir "$tmp" && [ -f "$tmp/$path" ]; then
    mv "$tmp/$path" "$final" && echo "  ✓ OK: $out"
  else
    echo "  ✗ FALHOU: $out  ($repo :: $path)"; rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
}

# Diffusion: Z-Image Turbo bf16 (~12GB). Pra GPU pequena (≤8GB), trocar pelo fp8/nvfp4.
dl Comfy-Org/z_image_turbo "split_files/diffusion_models/z_image_turbo_bf16.safetensors" \
   diffusion_models "z_image_turbo_bf16.safetensors"

# Text encoder: Qwen3-4B (o Z-Image usa Qwen3 como text encoder). VAE: ae (FLUX VAE).
dl Comfy-Org/z_image_turbo "split_files/text_encoders/qwen_3_4b.safetensors" \
   text_encoders "qwen_3_4b.safetensors"
dl Comfy-Org/z_image_turbo "split_files/vae/ae.safetensors" \
   vae "ae.safetensors"

# ── verificação: o build DEVE falhar se faltar qualquer arquivo ──────────────
echo "=== verificando arquivos baixados ==="
EXPECTED=(
  "diffusion_models/z_image_turbo_bf16.safetensors"
  "text_encoders/qwen_3_4b.safetensors"
  "vae/ae.safetensors"
)
MISSING=0
for f in "${EXPECTED[@]}"; do
  if [ -f "$VOL/$f" ]; then echo "  ✓ $f ($(du -h "$VOL/$f" | cut -f1))"; else echo "  ✗ FALTANDO: $f"; MISSING=1; fi
done
if [ "$MISSING" -ne 0 ]; then echo "✗ FATAL: modelos faltando — abortando build"; exit 1; fi
echo "✓ modelos prontos em $VOL (loras/ vazia — LoRA de personagem vem do R2 em runtime)"
