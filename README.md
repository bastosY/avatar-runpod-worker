# RunPod Serverless worker — branch `zimage-trainer` (treino de LoRA Z-Image)

Treina uma **LoRA de personagem Z-Image** via **Ostris ai-toolkit**, on-demand.
**1 POST = 1 personagem treinado**: recebe o dataset (charsheet) + config, treina, e sobe
`loras/<slug>.safetensors` no **R2**. O worker de inferência (branch `zimage`) consome essa
mesma LoRA. Roda em **4090 (24GB)**.

> Separado do worker de inferência: treino é job LONGO (~10-30min) e tem deps diferentes
> (ai-toolkit, não ComfyUI). Não misturar no endpoint de geração.

## Como funciona
- Base: `Tongyi-MAI/Z-Image-Turbo` (Apache 2.0) + **adapter de de-distillation**
  `ostris/zimage_turbo_training_adapterV2` (carregado SÓ no treino → evita "turbo drift";
  a LoRA final roda no modelo distilado rápido normal). Ambos **assados no HF cache** (build).
- `handler.py`: dataset (base64 ou R2 key + caption) → `config.yaml` → `ai-toolkit/run.py`
  → acha o `.safetensors` → upload R2.

## Contrato de input (RunPod `/run`)
```jsonc
{
  "input": {
    "slug": "lipe",
    "images": [
      { "name": "front.png", "data": "<base64>", "caption": "a 3d pixar style boy, lipe, front view" },
      { "key": "runs/lipe/medium.png", "caption": "lipe, waist up" }   // ou puxa do R2
    ],
    "config": { "trigger": "lipe", "steps": 3000, "rank": 16, "lr": 1e-4, "resolution": [1024] },
    "output_key": "loras/lipe.safetensors"   // opcional
  }
}
```
Resposta: `{ "ok": true, "key": "loras/lipe.safetensors", "seconds": 840, "images": 20 }`

## Instanciar no RunPod
1. **Serverless → New Endpoint → import from GitHub** → este repo, branch **`zimage-trainer`**.
2. GPU: **4090 (24GB)**. ⚠️ **Aumentar o Execution Timeout** (treino leva ~10-30min; o default
   serverless é curto). Min CUDA 12.4.
3. **Env vars** (R2): `BUCKET_ENDPOINT_URL`, `BUCKET_ACCESS_KEY_ID`, `BUCKET_SECRET_ACCESS_KEY`.
4. Build assa ~15GB (base + adapter no HF cache).

## ⚠️ A CONFIRMAR no 1º build (não chutar em produção)
O `config.yaml` segue o padrão do ai-toolkit, mas estes campos do **Z-Image** mudam entre
versões — validar contra o exemplo oficial do ai-toolkit (`config/examples`) e a doc do
adapter Ostris:
- `model.arch` (usei `"zimage"`) — nome exato da arquitetura no ai-toolkit.
- `model.assistant_lora_path` — campo/forma de carregar o adapter de de-distillation.
- Possível conflito de versão do **torch** (base 2.5.1 vs requirements do ai-toolkit).
Se o treino falhar, o handler retorna `stdout`/`stderr` do ai-toolkit no JSON — usar p/ ajustar.

## Pipeline (lado app, TS)
- `runTrainCharacterLora(slug)`: pega o charsheet do personagem (R2 keys) + captions →
  `POST /run` neste endpoint → guarda a `key` retornada no personagem.
- Inferência: worker `zimage` recebe `loras:[{name,key}]` e gera as cenas com a LoRA.
