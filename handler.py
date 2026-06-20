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
import time

import yaml
import runpod

BASE_MODEL = os.environ.get("ZIMAGE_BASE_MODEL", "Tongyi-MAI/Z-Image-Turbo")
# adapter de de-distillation (evita "turbo drift"). ID correto = sem "V2".
TRAIN_ADAPTER = os.environ.get("ZIMAGE_TRAIN_ADAPTER", "ostris/zimage_turbo_training_adapter")
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

    process = {
        "type": "sd_trainer",
        "training_folder": output_dir,
        "device": "cuda:0",
        "network": {"type": "lora", "linear": rank, "linear_alpha": rank},
        "save": {"dtype": "float16", "save_every": steps, "max_step_saves_to_keep": 1},
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

    yaml_path = _build_config(slug, dataset_dir, output_dir, cfg)
    print(f"trainer - slug={slug} imgs={n} steps={cfg.get('steps', 3000)} → ai-toolkit")

    t0 = time.time()
    proc = subprocess.run(
        ["python", os.path.join(AI_TOOLKIT, "run.py"), yaml_path],
        cwd=AI_TOOLKIT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return {
            "error": "ai-toolkit training failed",
            "returncode": proc.returncode,
            "stdout": proc.stdout[-3000:],
            "stderr": proc.stderr[-3000:],
        }

    saf = sorted(glob.glob(os.path.join(output_dir, "**", "*.safetensors"), recursive=True))
    if not saf:
        return {"error": "no .safetensors produced", "stdout": proc.stdout[-2000:]}
    lora = saf[-1]

    cli, bucket = _r2_client()
    if cli is None:
        return {"error": "R2 não configurado (defina BUCKET_* no endpoint)"}
    key = inp.get("output_key") or f"loras/{slug}.safetensors"
    cli.upload_file(lora, bucket, key)

    dt = round(time.time() - t0)
    print(f"trainer - done slug={slug} {dt}s → r2:{key}")
    try:
        shutil.rmtree(work)
    except Exception:
        pass
    return {"ok": True, "key": key, "seconds": dt, "images": n, "steps": int(cfg.get("steps", 3000))}


runpod.serverless.start({"handler": handler})
