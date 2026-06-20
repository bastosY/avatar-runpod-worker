"""
Worker serverless de TREINO de LoRA Z-Image (Ostris ai-toolkit).

Fluxo (1 POST = 1 personagem):
  input → baixa dataset (charsheet) → renderiza config.yaml do ai-toolkit →
  roda o treino → acha o .safetensors → sobe em loras/<slug>.safetensors no R2.

Contrato de input (RunPod /run):
{
  "input": {
    "slug": "lipe",                                  # nome de saída + key no R2
    "images": [                                      # dataset (5-30 imgs do charsheet)
      { "name": "front.png", "data": "<base64>", "caption": "a photo of <trigger>" },
      { "key": "runs/.../medium.png", "caption": "..." }   # ou puxa do R2 por key
    ],
    "config": {                                      # tudo opcional (defaults sensatos)
      "trigger": "lipe", "steps": 3000, "rank": 16, "lr": 1e-4,
      "resolution": [1024], "batch_size": 1, "optimizer": "adamw8bit"
    },
    "output_key": "loras/lipe.safetensors"           # opcional (default = loras/<slug>.safetensors)
  }
}
"""
import os
import base64
import glob
import shutil
import subprocess
import tempfile
import threading
import time

import yaml
import runpod

BASE_MODEL = os.environ.get("ZIMAGE_BASE_MODEL", "Tongyi-MAI/Z-Image-Turbo")
# adapter de de-distillation (evita "turbo drift"). O ai-toolkit quer o CAMINHO DO ARQUIVO
# (.safetensors), não o repo id — o arquivo é assado em /adapters (download_models.sh).
TRAIN_ADAPTER = os.environ.get("ZIMAGE_TRAIN_ADAPTER", "/adapters/zimage_turbo_training_adapter_v2.safetensors")
AI_TOOLKIT = os.environ.get("AI_TOOLKIT_DIR", "/ai-toolkit")


def _r2_client():
    """Cliente S3 (R2) a partir das BUCKET_*. Retorna (cliente, bucket) ou (None, None)."""
    raw = os.environ.get("BUCKET_ENDPOINT_URL", "")
    if not raw:
        return None, None
    try:
        import boto3
        from urllib.parse import urlparse

        u = urlparse(raw)
        cli = boto3.client(
            "s3",
            region_name="auto",
            endpoint_url=f"{u.scheme}://{u.netloc}",
            aws_access_key_id=os.environ.get("BUCKET_ACCESS_KEY_ID"),
            aws_secret_access_key=os.environ.get("BUCKET_SECRET_ACCESS_KEY"),
        )
        bucket = u.path.lstrip("/").split("/")[0] or "nynce"
        return cli, bucket
    except Exception as e:
        print(f"trainer - R2 client init failed: {e}")
        return None, None


def _write_dataset(images, dataset_dir):
    """Escreve as imagens (base64 ou R2 key) + captions sidecar (<img>.txt) no dataset_dir."""
    os.makedirs(dataset_dir, exist_ok=True)
    cli, bucket = _r2_client()
    n = 0
    for i, im in enumerate(images or []):
        im = im or {}
        name = im.get("name") or f"img_{i:03d}.png"
        path = os.path.join(dataset_dir, name)
        if im.get("data"):
            with open(path, "wb") as f:
                f.write(base64.b64decode(im["data"]))
        elif im.get("key") and cli is not None:
            cli.download_file(bucket, im["key"], path)
        else:
            print(f"trainer - img {name}: sem 'data'/'key' (ou R2 off) — pulando")
            continue
        caption = im.get("caption")
        if caption is not None:
            with open(os.path.splitext(path)[0] + ".txt", "w") as f:
                f.write(str(caption))
        n += 1
    return n


def _build_config(slug, dataset_dir, output_dir, cfg):
    """Renderiza o config.yaml do ai-toolkit p/ treinar LoRA de Z-Image."""
    steps = int(cfg.get("steps", 3000))
    rank = int(cfg.get("rank", 16))
    lr = float(cfg.get("lr", 1e-4))
    resolution = cfg.get("resolution", [1024])
    if isinstance(resolution, int):
        resolution = [resolution]

    ckpt_every = int(cfg.get("checkpoint_every", 500))  # salva checkpoint a cada N steps
    keep = int(cfg.get("keep_checkpoints", 100))        # mantém (quase) todos no disco
    process = {
        "type": "sd_trainer",
        "training_folder": output_dir,
        "device": "cuda:0",
        "network": {"type": "lora", "linear": rank, "linear_alpha": rank},
        "save": {"dtype": "float16", "save_every": ckpt_every, "max_step_saves_to_keep": keep},
        "datasets": [
            {
                "folder_path": dataset_dir,
                "caption_ext": "txt",
                "caption_dropout_rate": 0.05,
                "cache_latents_to_disk": True,
                "resolution": resolution,
            }
        ],
        "train": {
            "batch_size": int(cfg.get("batch_size", 1)),
            "steps": steps,
            "gradient_accumulation": 1,
            "train_unet": True,
            "train_text_encoder": False,
            "gradient_checkpointing": True,
            "noise_scheduler": "flowmatch",
            "optimizer": cfg.get("optimizer", "adamw8bit"),
            "lr": lr,
            "dtype": "bf16",
        },
        "model": {
            # VALIDADO no spike: arch="zimage" e assistant_lora_path são os campos certos do ai-toolkit.
            "name_or_path": BASE_MODEL,
            "arch": "zimage",
            "quantize": True,
        },
    }
    # de-distillation adapter — carregado SÓ no treino (evita "turbo drift"). Override por input
    # (config.training_adapter); string vazia/null = treinar SEM adapter (não recomendado).
    adapter = cfg.get("training_adapter", TRAIN_ADAPTER)
    if adapter:
        process["model"]["assistant_lora_path"] = adapter
    trigger = cfg.get("trigger")
    if trigger:
        process["trigger_word"] = trigger

    config = {
        "job": "extension",
        "config": {"name": slug, "process": [process]},
        "meta": {"name": slug, "version": "1.0"},
    }
    os.makedirs(output_dir, exist_ok=True)
    path = os.path.join(output_dir, "config.yaml")
    with open(path, "w") as f:
        yaml.safe_dump(config, f, sort_keys=False)
    return path


def _stable(path, min_age=8):
    """True se o arquivo não foi tocado nos últimos min_age s (provavelmente já escrito inteiro)."""
    try:
        return (time.time() - os.path.getmtime(path)) > min_age
    except OSError:
        return False


def _sweep_checkpoints(output_dir, cli, bucket, slug, uploaded, require_stable=True):
    """Sobe checkpoints .safetensors novos (e estáveis) pro R2 em loras/<slug>/<arquivo>."""
    for p in sorted(glob.glob(os.path.join(output_dir, "**", "*.safetensors"), recursive=True)):
        if p in uploaded:
            continue
        if require_stable and not _stable(p):
            continue
        key = f"loras/{slug}/{os.path.basename(p)}"
        try:
            cli.upload_file(p, bucket, key)
            uploaded[p] = key
            print(f"trainer - checkpoint → r2:{key}")
        except Exception as e:
            print(f"trainer - checkpoint upload failed {os.path.basename(p)}: {e}")


def handler(job):
    inp = job.get("input") or {}
    slug = inp.get("slug")
    if not slug:
        return {"error": "missing 'slug'"}

    images = inp.get("images") or []
    cfg = inp.get("config") or {}
    work = tempfile.mkdtemp(prefix=f"train_{slug}_")
    dataset_dir = os.path.join(work, "dataset")
    output_dir = os.path.join(work, "output")

    n = _write_dataset(images, dataset_dir)
    if n == 0:
        return {"error": "no training images (precisa de 'data' base64 ou 'key' do R2)"}

    cli, bucket = _r2_client()
    if cli is None:
        return {"error": "R2 não configurado (defina BUCKET_* no endpoint)"}

    yaml_path = _build_config(slug, dataset_dir, output_dir, cfg)
    print(f"trainer - slug={slug} imgs={n} steps={cfg.get('steps', 3000)} ckpt={cfg.get('checkpoint_every', 500)} → ai-toolkit")

    # uploader em background: sobe cada checkpoint pro R2 ENQUANTO treina → sobrevive a timeout
    # (se o job morrer no meio, os checkpoints já estão no R2) e dá visibilidade de progresso.
    t0 = time.time()
    uploaded = {}
    stop = threading.Event()

    def _watch():
        while not stop.is_set():
            _sweep_checkpoints(output_dir, cli, bucket, slug, uploaded)
            stop.wait(20)

    watcher = threading.Thread(target=_watch, daemon=True)
    watcher.start()

    proc = subprocess.run(
        ["python", os.path.join(AI_TOOLKIT, "run.py"), yaml_path],
        cwd=AI_TOOLKIT,
        capture_output=True,
        text=True,
    )

    stop.set()
    watcher.join(timeout=10)
    # varredura final: subprocess acabou → todos os arquivos estão escritos (sem checar estabilidade)
    _sweep_checkpoints(output_dir, cli, bucket, slug, uploaded, require_stable=False)

    if proc.returncode != 0:
        return {
            "error": "ai-toolkit training failed",
            "returncode": proc.returncode,
            "checkpoints": sorted(uploaded.values()),
            "stdout": proc.stdout[-3000:],
            "stderr": proc.stderr[-3000:],
        }
    if not uploaded:
        return {"error": "no .safetensors produced", "stdout": proc.stdout[-2000:]}

    # checkpoint final (maior step) também vira a key canônica loras/<slug>.safetensors
    final_path = sorted(uploaded.keys())[-1]
    canonical = inp.get("output_key") or f"loras/{slug}.safetensors"
    cli.upload_file(final_path, bucket, canonical)

    dt = round(time.time() - t0)
    print(f"trainer - done slug={slug} {dt}s → {len(uploaded)} checkpoints, final r2:{canonical}")
    try:
        shutil.rmtree(work)
    except Exception:
        pass
    return {
        "ok": True,
        "key": canonical,
        "checkpoints": sorted(uploaded.values()),
        "seconds": dt,
        "images": n,
        "steps": int(cfg.get("steps", 3000)),
    }


runpod.serverless.start({"handler": handler})
