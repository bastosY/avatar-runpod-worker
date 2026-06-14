# RunPod Serverless worker — branch `image` (Qwen-Image-Edit 2511)

Worker de **geração de IMAGEM** pro RunPod Serverless. Substitui o Nano Banana Pro:
edição/consistência de personagem a partir de imagens de referência, custo ~zero por
imagem (só GPU). Endpoint **separado** do worker de vídeo.

> Outras branches: `main`/`h100`/`rtx5090` = worker de **vídeo** (WAN/InfiniteTalk).

## Modelo
Qwen-Image-Edit 2511, fp8, com **Lightning 4-step** embutido (merged comfyui):
- `diffusion_models/qwen_image_edit_2511_fp8_4steps.safetensors` (~20GB)
- `text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors`
- `vae/qwen_image_vae.safetensors`

Nodes nativos do ComfyUI (UNETLoader, CLIPLoader, VAELoader, TextEncodeQwenImageEditPlus,
KSampler, VAEDecode/Encode, SaveImage) — **sem custom nodes** → worker leve.

## Arquivos
- `Dockerfile` — worker-comfyui + ComfyUI master + modelos assados (sem volume).
- `download_models.sh` — baixa os ~25GB no BUILD (imagem autossuficiente).
- `handler.py` — sobe a saída (SaveImage → "images") pro R2 via boto3 (env BUCKET_*).

## Instanciar no RunPod (sem volume)
1. **Serverless → New Endpoint → import from GitHub** → este repo, branch **`image`**.
2. GPU: **barata serve** (Qwen fp8 cabe em 24GB; image é leve). Min CUDA 12.8.
3. **Env vars** (saída no R2): `BUCKET_ENDPOINT_URL`, `BUCKET_ACCESS_KEY_ID`, `BUCKET_SECRET_ACCESS_KEY`.
4. Build assa ~25GB (uma vez); rebuilds de handler são rápidos (cache dos modelos).

## App
Apontar `IMAGE_BACKEND=runpod` + `RUNPOD_IMAGE_ENDPOINT_ID` no app; o workflow JSON
do Qwen vai em `workflows/image/` do repo da plataforma.
