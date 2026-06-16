#!/usr/bin/env bash
# Baixa os modelos do Qwen-Image-Edit 2511 (4-step). Roda NO BUILD (assa na imagem).
# Salva com os NOMES que o workflow espera. ~25GB total.
# IMPORTANTE: FALHA o build se algum arquivo não baixar (não deixa imagem sem modelo).
set -uo pipefail

VOL="${MODELS_DIR:-/comfyui/models}"
mkdir -p "$VOL"/{diffusion_models,text_encoders,vae,loras}
echo "=== baixando modelos Qwen-Image-Edit para $VOL ==="

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

# Diffusion: BASE puro (NÃO-merged, sem lightning embutido) — ~20GB.
# Destrava cfg>1 (negative nativo) rodando steps cheios; OU empilhar a LoRA de
# lightning abaixo p/ modo rápido. (branch image-base = plano B "modelo puro + LoRAs".)
dl lightx2v/Qwen-Image-Edit-2511-Lightning \
   "qwen_image_edit_2511_fp8_e4m3fn_scaled.safetensors" \
   diffusion_models "qwen_image_edit_2511_fp8_base.safetensors"

# Text encoder (Qwen2.5-VL 7B, fp8) e VAE — do repo base Comfy-Org.
dl Comfy-Org/Qwen-Image_ComfyUI "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
   text_encoders "qwen_2.5_vl_7b_fp8_scaled.safetensors"
dl Comfy-Org/Qwen-Image_ComfyUI "split_files/vae/qwen_image_vae.safetensors" \
   vae "qwen_image_vae.safetensors"

# LoRA de LIGHTNING (aceleração, GENÉRICA) — separada, p/ empilhar com strength controlável.
# strength 0 = base puro (cfg alto, ~25 steps); strength 1 + 4 steps = igual ao merged (cfg=1).
dl lightx2v/Qwen-Image-Edit-2511-Lightning \
   "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors" \
   loras "qwen_lightning_4steps.safetensors"

# LoRA de CÂMERA (genérica, NÃO de personagem) — multi-angle p/ character sheet.
# Formato de prompt: "<sks> [azimuth] [elevation] [distance]". 1 arquivo serve todos.
dl fal/Qwen-Image-Edit-2511-Multiple-Angles-LoRA \
   "qwen-image-edit-2511-multiple-angles-lora.safetensors" \
   loras "qwen_camera_angles.safetensors"

# ── verificação: o build DEVE falhar se faltar qualquer arquivo ──────────────
echo "=== verificando arquivos baixados ==="
EXPECTED=(
  "diffusion_models/qwen_image_edit_2511_fp8_base.safetensors"
  "text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
  "vae/qwen_image_vae.safetensors"
  "loras/qwen_lightning_4steps.safetensors"
  "loras/qwen_camera_angles.safetensors"
)
MISSING=0
for f in "${EXPECTED[@]}"; do
  if [ -f "$VOL/$f" ]; then echo "  ✓ $f ($(du -h "$VOL/$f" | cut -f1))"; else echo "  ✗ FALTANDO: $f"; MISSING=1; fi
done
if [ "$MISSING" -ne 0 ]; then echo "✗ FATAL: modelos faltando — abortando build"; exit 1; fi
echo "✓ todos os modelos prontos em $VOL"
