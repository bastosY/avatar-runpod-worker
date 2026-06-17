#!/usr/bin/env bash
# Baixa o Qwen-Image 2512 (TEXT-TO-IMAGE). Roda NO BUILD (assa na imagem). ~30GB.
# Worker de CRIAÇÃO: gera personagem do zero (realista) → a imagem vira referência no 2511 (edit).
# IMPORTANTE: FALHA o build se algum arquivo não baixar (não deixa imagem sem modelo).
set -uo pipefail

VOL="${MODELS_DIR:-/comfyui/models}"
mkdir -p "$VOL"/{diffusion_models,text_encoders,vae,loras}
echo "=== baixando Qwen-Image 2512 (t2i) para $VOL ==="

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

# Diffusion: Qwen-Image 2512 fp8 (TEXT-TO-IMAGE, realismo nativo). ~20GB.
dl Comfy-Org/Qwen-Image_ComfyUI "split_files/diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors" \
   diffusion_models "qwen_image_2512_fp8.safetensors"

# Text encoder (Qwen2.5-VL 7B, fp8) e VAE — mesmos do 2511.
dl Comfy-Org/Qwen-Image_ComfyUI "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
   text_encoders "qwen_2.5_vl_7b_fp8_scaled.safetensors"
dl Comfy-Org/Qwen-Image_ComfyUI "split_files/vae/qwen_image_vae.safetensors" \
   vae "qwen_image_vae.safetensors"

# ── verificação: o build DEVE falhar se faltar qualquer arquivo ──────────────
echo "=== verificando arquivos baixados ==="
EXPECTED=(
  "diffusion_models/qwen_image_2512_fp8.safetensors"
  "text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
  "vae/qwen_image_vae.safetensors"
)
MISSING=0
for f in "${EXPECTED[@]}"; do
  if [ -f "$VOL/$f" ]; then echo "  ✓ $f ($(du -h "$VOL/$f" | cut -f1))"; else echo "  ✗ FALTANDO: $f"; MISSING=1; fi
done
if [ "$MISSING" -ne 0 ]; then echo "✗ FATAL: modelos faltando — abortando build"; exit 1; fi
echo "✓ todos os modelos prontos em $VOL"
