#!/usr/bin/env bash
# Baixa os modelos do InfiniteTalk. Roda NO BUILD (assa na imagem) — MODELS_DIR
# aponta p/ /comfyui/models. Salva com os NOMES que o workflow espera.
set -uo pipefail

VOL="${MODELS_DIR:-/comfyui/models}"
mkdir -p "$VOL"/{diffusion_models,text_encoders,vae,clip_vision,loras}
echo "=== baixando modelos para $VOL ==="
echo "hf CLI: $(command -v hf || echo 'NAO ENCONTRADO')"

dl() { # repo  path-no-repo  pasta-destino  nome-de-saida
  local repo="$1" path="$2" dest="$3" out="$4"
  local final="$VOL/$dest/$out"
  if [ -f "$final" ]; then echo "✓ já existe: $out"; return; fi
  echo "↓ $out  ($repo :: $path)"
  local tmp; tmp=$(mktemp -d)
  if hf download "$repo" "$path" --local-dir "$tmp" && [ -f "$tmp/$path" ]; then
    mv "$tmp/$path" "$final" && echo "  ✓ OK: $out"
  else
    echo "  ✗ FALHOU: $out"; rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
}

dl Kijai/WanVideo_comfy "Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors" diffusion_models "Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"
dl Kijai/WanVideo_comfy "InfiniteTalk/Wan2_1-InfiniTetalk-Single_fp16.safetensors" diffusion_models "Wan2_1-InfiniTetalk-Single_fp16.safetensors"
dl Kijai/WanVideo_comfy "umt5-xxl-enc-bf16.safetensors" text_encoders "umt5-xxl-enc-bf16.safetensors"
dl Kijai/WanVideo_comfy "Wan2_1_VAE_bf16.safetensors" vae "wan_2.1_vae.safetensors"
dl Kijai/WanVideo_comfy "Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors" loras "lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
dl Comfy-Org/Wan_2.1_ComfyUI_repackaged "split_files/clip_vision/clip_vision_h.safetensors" clip_vision "clip_vision_h.safetensors"

echo "=== conteúdo final ==="
find "$VOL" -type f -exec du -h {} \; 2>/dev/null
echo "✓ modelos prontos em $VOL"
