#!/usr/bin/env bash
# Baixa os modelos do InfiniteTalk para o Network Volume (/runpod-volume/models).
# Idempotente: só baixa o que ainda não existe. Roda no 1º cold start.
set -euo pipefail

VOL=/runpod-volume/models
mkdir -p "$VOL"/{diffusion_models,text_encoders,vae,clip_vision,loras}

dl() { # repo  arquivo-no-repo  pasta-destino
  local repo="$1" file="$2" dest="$3"
  local out="$VOL/$dest/$(basename "$file")"
  if [ -f "$out" ]; then echo "✓ já existe: $(basename "$file")"; return; fi
  echo "↓ baixando: $file"
  hf download "$repo" "$file" --local-dir "$VOL/$dest/_tmp" >/dev/null
  mv "$VOL/$dest/_tmp/$file" "$out" 2>/dev/null || mv "$VOL/$dest/_tmp/$(basename "$file")" "$out"
  rm -rf "$VOL/$dest/_tmp"
}

# Kijai/WanVideo_comfy hospeda a maioria. Ajustar os paths se algum mudar.
# Modelo de difusão: 720p nativo (Wan I2V 14B 720p fp8).
dl Kijai/WanVideo_comfy "split_files/diffusion_models/Wan2_1-I2V-14B-720p_fp8_e4m3fn_scaled_KJ.safetensors" diffusion_models || \
  dl Kijai/WanVideo_comfy "Wan2_1-I2V-14B-720p_fp8_e4m3fn_scaled_KJ.safetensors" diffusion_models

dl Kijai/WanVideo_comfy "Wan2_1-InfiniTetalk-Single_fp16.safetensors" diffusion_models
dl Kijai/WanVideo_comfy "umt5-xxl-enc-bf16.safetensors" text_encoders
dl Kijai/WanVideo_comfy "Wan2_1_VAE_bf16.safetensors" vae || dl Kijai/WanVideo_comfy "wan_2.1_vae.safetensors" vae
# LoRA distill: só existe a 480p — funciona no modelo 720p (distila steps, não resolução).
dl Kijai/WanVideo_comfy "lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors" loras

# clip_vision_h (do repo do comfyanonymous)
dl Comfy-Org/sigclip_vision_384 "sigclip_vision_patch14_384.safetensors" clip_vision || \
  dl openai/clip-vit-large-patch14 "clip_vision_h.safetensors" clip_vision || true

echo "✓ modelos prontos em $VOL"
