# RunPod Serverless worker — branch `zimage` (Z-Image Turbo + LoRA de personagem)

Worker de **geração de IMAGEM** com **LoRA de personagem**: a identidade do personagem
mora nas weights de uma LoRA (treinada a partir do charsheet), e o worker a **baixa em
runtime do R2** — sem rebuild por personagem. Cena/roupa/pose vão no prompt. Custo ~zero por
imagem (só GPU). Endpoint **separado** dos demais.

> Por que Z-Image: 6B, **Apache 2.0** (comercial liberado), inferência baratíssima
> (~$0.0085/MP), LoRA-friendly. Alternativa ao reference-edit do Qwen p/ escalar a dezenas
> de personagens com consistência travada na LoRA.

## Modelos (assados na imagem, ~20GB)
- `diffusion_models/z_image_turbo_bf16.safetensors` (~12GB) — Z-Image Turbo (arch Lumina2)
- `text_encoders/qwen_3_4b.safetensors` — text encoder Qwen3-4B
- `vae/ae.safetensors` — VAE
- `loras/` — **VAZIA**; a LoRA de personagem vem do R2 em runtime

Fonte: `Comfy-Org/z_image_turbo` (HF). GPU pequena (≤8GB): trocar o bf16 pelo fp8/nvfp4 no
`download_models.sh`.

## Custom node (OBRIGATÓRIO)
[`Comfyui-ZiT-Lora-loader`](https://github.com/capitan01R/Comfyui-ZiT-Lora-loader) — nó
**"Z-Image Turbo LoRA Loader"**. O `LoraLoader` genérico do ComfyUI **dropa silenciosamente
a atenção** no Z-Image (QKV fundido) → a LoRA carrega mas a identidade NÃO transfere. Este nó
funde Q/K/V no formato nativo (`auto_convert_qkv`). **Sem ele a LoRA é inútil.**

## Arquivos
- `Dockerfile` — worker-comfyui + ComfyUI master + ZiT loader + modelos assados (sem volume).
- `download_models.sh` — baixa os ~20GB no BUILD (imagem autossuficiente).
- `handler.py` — (1) `ensure_loras`: baixa a LoRA do R2/URL p/ `models/loras` (cache em disco)
  antes de rodar; (2) sobe a saída (SaveImage → "images") pro R2 via boto3.

## Contrato de input (RunPod `/run`)
```jsonc
{
  "input": {
    "workflow": { /* grafo ComfyUI: ...Z-Image Turbo LoRA Loader... */ },
    "loras": [
      { "name": "lipe.safetensors", "key": "loras/lipe.safetensors" }   // baixa do R2 (boto3)
      // ou: { "name": "lipe.safetensors", "url": "https://..." }        // baixa de URL
    ]
  }
}
```
- `name` = nome do arquivo que o workflow referencia no nó ZiT (`lora_name`).
- `key` = caminho no bucket R2 (usa as mesmas `BUCKET_*` do upload). `url` = alternativa direta.
- Cache: se `models/loras/<name>` já existe (warm worker), pula o download.

## Instanciar no RunPod (sem volume)
1. **Serverless → New Endpoint → import from GitHub** → este repo, branch **`zimage`**.
2. GPU: 24GB folga (bf16 12GB + encoder). Z-Image é leve/rápido (8 steps). Min CUDA 12.8.
3. **Env vars** (R2, p/ saída E p/ baixar LoRA por `key`): `BUCKET_ENDPOINT_URL`,
   `BUCKET_ACCESS_KEY_ID`, `BUCKET_SECRET_ACCESS_KEY`.
4. Build assa ~20GB (uma vez); rebuilds de handler são rápidos (cache dos modelos).

## App (próximas fases)
- Treino da LoRA (fal `z-image-trainer` OU `comfyUI-Realtime-Lora` no próprio worker) →
  `.safetensors` salvo no R2 em `loras/<slug>.safetensors`.
- `RUNPOD_ZIMAGE_ENDPOINT_ID` no app; `buildZImage()` (TS) monta o workflow t2i com o nó
  **Z-Image Turbo LoRA Loader** + `loras:[{name,key}]` no payload.

> ⚠️ A montar/validar com o ComfyUI rodando: o `class_type` exato do nó ZiT e os nós de
> sampler do Z-Image (steps≈8, cfg baixo) — confirmar via `/object_info` do endpoint.
