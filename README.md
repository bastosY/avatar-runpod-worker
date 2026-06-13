# RunPod Serverless worker — ComfyUI + WAN/InfiniteTalk

Worker custom pra rodar o workflow InfiniteTalk no **RunPod Serverless** (sem pod).
RunPod builda a imagem direto deste repo no GitHub.

## Arquivos
- `Dockerfile` — worker-comfyui + WanVideoWrapper + VideoHelperSuite.
- `download_models.sh` — baixa os modelos (~50GB) pro Network Volume no 1º start.
- `extra_model_paths.yaml` — aponta o ComfyUI pros modelos em `/runpod-volume/models`.
- `start.sh` — roda o download (idempotente) e inicia o worker.

## Passos no RunPod (UI, sem Docker local, sem pod)
1. **Network Volume**: Storage → New Network Volume (ex.: 100GB) na **mesma região** do endpoint
   (fixe o endpoint numa região só — volume é regional). Sugestão: **US-NC-1**.
2. **Subir este repo pro GitHub** (pasta `runpod-worker/` como raiz do repo, ou ajustar o build context).
3. **Serverless → New Endpoint → import from GitHub**: aponte pro repo. RunPod builda a imagem.
4. No endpoint: **GPU 24GB (RTX 4090)**, **anexar o Network Volume**, região = a do volume.
5. **1ª requisição** dispara o download dos modelos pro volume (lento, ~10-20min uma vez).
   Mande um job de "aquecimento" e aguarde; os próximos cold starts já acham os modelos.

## Notas
- Os paths do HF em `download_models.sh` são o melhor palpite; se algum 404, ajustar
  (conferir `huggingface.co/Kijai/WanVideo_comfy`).
- O `wav2vec` (`chinese-wav2vec2-base`) é baixado pelo próprio nó em runtime.
- Depois disso, apontar o app: `comfyui.ts` em modo RunPod (`/run` + `/status`).
