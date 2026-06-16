# RunPod worker — branch `charsheet` (Qwen character sheet completo)

Worker de IMAGEM mais rico (endpoint serverless SEPARADO do `image`). Método
"Mickmumpitz-no-Qwen", tudo em Qwen-Image-Edit 2511 (sem Flux):
- **Ângulos:** camera LoRA (fal multi-angle) — turnaround 360°.
- **Pose precisa / pose-grid:** ControlNet-Union (pose/openpose) + template de esqueleto.
- **Expressões:** LivePortrait (ExpressionEditor) — warp do rosto, identidade 100%.
- **Qualidade:** FaceDetailer (Impact-Pack + yolov8) + UltimateSDUpscale (4x-UltraSharp).

## Modelos assados (~26GB)
- diffusion_models/qwen_image_edit_2511_fp8_4steps.safetensors
- text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors · vae/qwen_image_vae.safetensors
- loras/qwen_camera_angles.safetensors  (fal multi-angle)
- controlnet/qwen_controlnet_union.safetensors  (InstantX — ⚠️ compat c/ Edit-2511 a verificar)
- upscale_models/4x-UltraSharp.pth · ultralytics/bbox/face_yolov8m.pt
- liveportrait/*.safetensors  (Kijai, 5 arquivos)

## Custom nodes
Impact-Pack, Impact-Subpack, UltimateSDUpscale, AdvancedLivePortrait (+ insightface).

## Deploy
Serverless → New Endpoint → import GitHub → branch `charsheet`. GPU 24GB+, Min CUDA 12.8,
env vars BUCKET_* (R2). ⚠️ Build pesado/longo; se falhar, ver ordem de depuração no Dockerfile.
