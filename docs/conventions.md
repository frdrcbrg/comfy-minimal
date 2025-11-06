# Comfy Minimal – Developer Conventions

This document outlines how to work in this repository from a developer point of view: build targets, runtime behavior, environment, dependency management, customization points, quality gates, and troubleshooting.

## Stack Overview

- **Base OS**: Ubuntu 22.04
- **GPU stack**:
  - Regular image: CUDA 12.4, stable PyTorch via upstream requirements
  - RTX 5090 image: CUDA 12.8, PyTorch Nightly (explicit cu128 wheels)
- **Python**: 3.12 (set as system default inside the image)
- **Package manager**: pip + uv (uv used for fast installs; `UV_LINK_MODE=copy`)
- **Tools bundled**: FileBrowser (port 8080), OpenSSH server (port 22), FFmpeg (NVENC), civitdl (CivitAI model downloader), Hugging Face CLI (huggingface-cli), common CLI tools
- **Primary app**: ComfyUI, with pre-installed custom nodes

## Repository Layout

- `Dockerfile` – Regular image (CUDA 12.4)
- `Dockerfile.5090` – RTX 5090 image (CUDA 12.8 + PyTorch cu128)
- `start.sh` – Runtime bootstrap for regular image
- `start.5090.sh` – Runtime bootstrap for 5090 image
- `docker-bake.hcl` – Buildx bake targets (`regular`, `dev`, `rtx5090`)
- `README.md` – User-facing overview
- `docs/conventions.md` – This document

At runtime, the container uses:

- `/workspace/runpod-slim/ComfyUI` – ComfyUI checkout and virtual environment
- `/workspace/runpod-slim/comfyui_args.txt` – Optional line-delimited ComfyUI args
- `/workspace/runpod-slim/filebrowser.db` – FileBrowser DB

## Build Targets

Use Docker Buildx Bake with the provided HCL file.

- `regular` (default production):
  - Dockerfile: `Dockerfile`
  - Tag: `ghcr.io/frdrcbrg/comfy-minimal:${TAG}` (defaults to `latest`)
  - Platform: `linux/amd64`
- `dev` (local testing):
  - Dockerfile: `Dockerfile`
  - Tag: `ghcr.io/frdrcbrg/comfy-minimal:dev`
  - Output: local docker image (not pushed)
- `rtx5090` (CUDA 12.8 + latest torch):
  - Dockerfile: `Dockerfile.5090`
  - Tag: `ghcr.io/frdrcbrg/comfy-minimal:${TAG}-5090`

Example commands:

```bash
# Build default regular target
docker buildx bake -f docker-bake.hcl regular

# Build dev image locally
docker buildx bake -f docker-bake.hcl dev

# Build 5090 variant
docker buildx bake -f docker-bake.hcl rtx5090
```

Build args and env:

- `TAG` variable in `docker-bake.hcl` controls the tag suffix (default `latest`).
- `IMAGE_REF` variable in `docker-bake.hcl` controls the image repository (default `ghcr.io/frdrcbrg/comfy-minimal`).
- Build uses BuildKit inline cache.

## Runtime Behavior

Startup is handled by `start.sh` (or `start.5090.sh` for the 5090 image):

- Initializes SSH server. If `PUBLIC_KEY` is set, it is added to `~/.ssh/authorized_keys`; otherwise a random root password is generated and printed to logs.
- Exports selected env vars broadly to `/etc/environment`, PAM, and `~/.ssh/environment` for non-interactive shells.
- Configures civitdl with `CIVITAI_API_KEY` if provided.
- Configures Hugging Face CLI with `HF_TOKEN` if provided.
- Initializes and starts FileBrowser on port 8080 (root `/workspace`). Default admin user is created on first run.
- Ensures `comfyui_args.txt` exists.
- Clones ComfyUI and preselected custom nodes on first run, then creates a Python 3.12 venv and installs dependencies using `uv`.
- **Sets up persistent model storage**: Creates `/workspace/models/` directory structure and symlinks all ComfyUI model subdirectories to it. This ensures models persist across container restarts.
- **Sets up persistent workflow storage**: Creates `/workspace/workflows/` and symlinks `ComfyUI/user/default/workflows` to it. This ensures workflows persist across container restarts.
- **Auto-downloads CivitAI models**: Reads `/workspace/civitai_models.txt` and downloads configured models. Creates example file if it doesn't exist. Uses civitdl's built-in caching to skip already-downloaded models.
- **Auto-downloads Hugging Face models**: Reads `/workspace/huggingface_models.txt` and downloads configured models. Creates example file if it doesn't exist. Uses huggingface-cli with HF_TOKEN for authentication.
- **Displays startup banner**: Shows system info (GPU, IP, variant), service URLs, configuration status (API keys, SSH method), storage locations, and useful commands. Provides immediate visibility into container state.
- Starts ComfyUI with fixed args `--listen 0.0.0.0 --port 8188` plus any custom args from `comfyui_args.txt`.

Differences in 5090 script:

- Virtualenv path: `.venv-cu128`
- Masks torch-related lines in ComfyUI `requirements.txt` and installs torch/cu128 wheels explicitly: `torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128`.

## Ports

- 8188 – ComfyUI
- 8080 – FileBrowser
- 22 – SSH

Expose settings are declared in Dockerfiles.

## Environment Variables

Recognized at runtime by the start scripts:

- `PUBLIC_KEY` – If provided, enables key-based SSH for root; otherwise a random password is generated and printed.
- `CIVITAI_API_KEY` – If set, exported system-wide for use with civitdl. Allows downloading models from CivitAI without specifying the API key in each command.
- `HF_TOKEN` – If set, automatically logs in to Hugging Face CLI. Enables access to private/gated models and upload capabilities.
- `HF_HOME` – Optional. If set, specifies custom location for Hugging Face cache directory.
- GPU/CUDA-related environment variables are propagated (`CUDA*`, `LD_LIBRARY_PATH`, `PYTHONPATH`, and `RUNPOD_*` vars if present in the environment).

## Dependency Management

- Python 3.12 is the default interpreter in the image.
- Venv location:
  - Regular: `/workspace/runpod-slim/ComfyUI/.venv`
  - 5090: `/workspace/runpod-slim/ComfyUI/.venv-cu128`
- `uv` is used for dependency installation for speed and reproducibility.
- Regular image installs ComfyUI `requirements.txt` as-is.
- 5090 image comments out torch-related requirements and installs CUDA 12.8 torch wheels explicitly.
- Custom nodes: repos are cloned into `ComfyUI/custom_nodes/`. On first run and subsequent starts, the script attempts to install each node’s `requirements.txt`, run `install.py`, or `setup.py` if present.

Preinstalled custom nodes (initial set):

- `ComfyUI-Manager` (ltdrdata)
- `ComfyUI-KJNodes` (kijai)
- `Civicomfy` (MoonGoblinDev)

## Customization Points

- `comfyui_args.txt` – Add one CLI arg per line; comments starting with `#` are ignored. These are appended after fixed args.
- Add/remove custom nodes by editing the `CUSTOM_NODES` array in the start script(s), or pre-baking them into the image.
- Additional system packages: modify the respective Dockerfile `apt-get install` lines.
- Python packages: extend installation blocks in the start script after venv activation. Prefer `uv pip install --no-cache ...`.

## Persistent Model Storage

The container implements automatic model persistence via symlinks:

- **Location**: `/workspace/models/` is the persistent storage location
- **Symlinks**: Each ComfyUI model subdirectory (`checkpoints`, `loras`, `vae`, etc.) is symlinked to `/workspace/models/{subdir}`
- **Function**: `setup_model_symlinks()` in both start scripts handles setup
- **Behavior**:
  - Creates `/workspace/models/` and all subdirectories if they don't exist
  - Backs up existing ComfyUI model directories before creating symlinks (e.g., `models/checkpoints.bak`)
  - Creates symlinks from ComfyUI models directory to persistent storage
  - Runs after ComfyUI setup but before ComfyUI starts

Supported model subdirectories:
- `checkpoints`, `loras`, `vae`, `embeddings`, `hypernetworks`, `controlnet`, `upscale_models`, `clip`, `clip_vision`, `style_models`, `unet`

This ensures all models stored in `/workspace/models/` persist across container restarts, which is critical for RunPod deployments where `/workspace` is typically mounted as persistent storage.

## Persistent Workflow Storage

The container implements automatic workflow persistence via symlinks:

- **Location**: `/workspace/workflows/` is the persistent storage location
- **Symlink**: `ComfyUI/user/default/workflows` is symlinked to `/workspace/workflows`
- **Function**: `setup_workflow_symlinks()` in both start scripts handles setup
- **Behavior**:
  - Creates `/workspace/workflows/` if it doesn't exist
  - Creates `ComfyUI/user/default/` directory structure if needed
  - Backs up existing ComfyUI workflows directory before creating symlink (as `workflows.bak`)
  - Copies any existing workflows to persistent storage
  - Creates symlink from ComfyUI workflows directory to persistent storage
  - Runs after model symlinks but before auto-downloads

This ensures all workflows saved in ComfyUI persist across container restarts, which is critical for RunPod deployments where `/workspace` is typically mounted as persistent storage.

## CivitAI Auto-Download

The container supports automatic model downloading from CivitAI on startup:

- **Configuration file**: `/workspace/civitai_models.txt`
- **Format**: `MODEL_ID CATEGORY` (one per line)
- **Function**: `auto_download_civitai_models()` in both start scripts
- **Behavior**:
  - Creates example file if it doesn't exist
  - Reads file on every container start (after model symlinks are set up)
  - Parses each line as `MODEL_ID CATEGORY`
  - Validates model ID is numeric
  - Defaults to `checkpoints` category if not specified
  - Uses civitdl with the configured API key (from `CIVITAI_API_KEY` env var)
  - civitdl's built-in caching skips already-downloaded models
  - Continues downloading other models if one fails

Example `/workspace/civitai_models.txt`:
```text
# CivitAI Model Auto-Download List
123456 checkpoints
789012 loras
456789 controlnet
```

This provides a declarative way to manage model downloads across container restarts, ideal for RunPod templates where users want consistent model availability.

## Hugging Face Auto-Download

The container also supports automatic model downloading from Hugging Face Hub on startup:

- **Configuration file**: `/workspace/huggingface_models.txt`
- **Format**: `REPO_ID CATEGORY [REVISION]` (one per line)
- **Function**: `auto_download_huggingface_models()` in both start scripts
- **Behavior**:
  - Creates example file if it doesn't exist
  - Reads file on every container start (after CivitAI download)
  - Parses each line as `REPO_ID CATEGORY [REVISION]`
  - Validates repo_id is not empty
  - Defaults to `checkpoints` category if not specified
  - Converts repository names with slashes to underscores (e.g., `username/model` → `username_model`)
  - Downloads to `/workspace/models/{category}/{repo_name}`
  - Supports optional REVISION parameter (e.g., `main`, `fp16`, branch/tag names)
  - Uses huggingface-cli with HF_TOKEN for authentication if configured
  - huggingface-cli's built-in caching handles already-downloaded models
  - Continues downloading other models if one fails

Example `/workspace/huggingface_models.txt`:
```text
# Hugging Face Model Auto-Download List
stabilityai/stable-diffusion-xl-base-1.0 checkpoints
runwayml/stable-diffusion-v1-5 checkpoints fp16
username/my-lora loras
```

Key differences from CivitAI auto-download:
- Uses repository IDs instead of numeric model IDs
- Supports revision parameter for specific branches/tags
- Repository names are converted to filesystem-safe directory names
- Requires HF_TOKEN for private/gated models

## Dev Conventions

- Keep images lean. Prefer runtime install via `uv` over baking large wheels unless required (e.g., 5090 torch wheels).
- Avoid changing ports; they are referenced by external templates (RunPod/UI tooling).
- Use Python 3.12. Do not downgrade in scripts.
- When adding new env vars needed by downstream processes, ensure they are exported in `export_env_vars()` the same way as others.
- For new custom nodes, ensure idempotent installs: the loop checks for `requirements.txt`, `install.py`, and `setup.py`.
- Shell scripting: keep `set -e` at top; prefer explicit guards; write idempotent steps safe to re-run.
- Model storage: Always use `/workspace/models/` in documentation and examples for persistent model storage.

## Local Development Tips

- Use the `dev` target to build a locally loadable image without pushing:
  ```bash
  docker buildx bake -f docker-bake.hcl dev
  docker run --rm -p 8188:8188 -p 8080:8080 -p 2222:22 \
    -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
    -v "$PWD/workspace":/workspace \
    runpod/comfyui:dev
  ```
- Mount a host `workspace` to persist ComfyUI, args, and FileBrowser DB.

## Troubleshooting

- ComfyUI not reachable on 8188:
  - Check `/workspace/runpod-slim/comfyui.log` (tailing in foreground).
  - Ensure `comfyui_args.txt` doesn't contain invalid flags (comments with `#` are okay).
- SSH access:
  - If no `PUBLIC_KEY` is provided, a random root password is generated and printed to stdout. Check container logs.
  - Ensure port 22 is mapped from the host, e.g., `-p 2222:22`.
- GPU/torch issues on 5090 image:
  - Verify you’re running the `-5090` tag.
  - Torch builds are installed from `https://download.pytorch.org/whl/cu128`; confirm compatibility with the host driver.

## Release & Tagging

- Default tag base is `slim` via `TAG` in `docker-bake.hcl`.
- For 5090 builds, the pushed tag is `${TAG}-5090`.
- Keep `README.md` ports and features in sync when changing defaults.

## License

- GPLv3 as per `LICENSE`.
