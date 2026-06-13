#!/usr/bin/env bash
# Baixa os modelos do InfiniteTalk para o Network Volume (/runpod-volume/models).
# Idempotente. Salva com os NOMES que o workflow espera (renomeia na hora).
set -euo pipefail

VOL=/runpod-volume/models
mkdir -p "$VOL"/{diffusion_models,text_encoders,vae,clip_vision,loras}

dl() { # repo  path-no-repo  pasta-destino  nome-de-saida
  local repo="$1" path="$2" dest="$3" out="$4"
  local final="$VOL/$dest/$out"
  if [ -f "$final" ]; then echo "✓ já existe: $out"; return; fi
  echo "↓ $out  ($repo :: $path)"
  local tmp; tmp=$(mktemp -d)
  hf download "$repo" "$path" --local-dir "$tmp" >/dev/null
  mv "$tmp/$path" "$final"
  rm -rf "$tmp"
}

# diffusion (720p) + InfiniteTalk
dl Kijai/WanVideo_comfy "split_files/diffusion_models/Wan2_1-I2V-14B-720p_fp8_e4m3fn_scaled_KJ.safetensors" diffusion_models "Wan2_1-I2V-14B-720p_fp8_e4m3fn_scaled_KJ.safetensors"
dl Kijai/WanVideo_comfy "InfiniteTalk/Wan2_1-InfiniTetalk-Single_fp16.safetensors" diffusion_models "Wan2_1-InfiniTetalk-Single_fp16.safetensors"
# text encoder
dl Kijai/WanVideo_comfy "umt5-xxl-enc-bf16.safetensors" text_encoders "umt5-xxl-enc-bf16.safetensors"
# vae (renomeia p/ o nome do workflow)
dl Kijai/WanVideo_comfy "Wan2_1_VAE_bf16.safetensors" vae "wan_2.1_vae.safetensors"
# lora distill (subpasta Lightx2v/)
dl Kijai/WanVideo_comfy "Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors" loras "lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
# clip vision (de outro repo)
dl Comfy-Org/Wan_2.1_ComfyUI_repackaged "split_files/clip_vision/clip_vision_h.safetensors" clip_vision "clip_vision_h.safetensors"

echo "✓ modelos prontos em $VOL"
