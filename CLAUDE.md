# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Comfy Minimal is a highly optimized Docker container (~650MB) for running ComfyUI on RunPod. It provides a complete environment with ComfyUI, FileBrowser, SSH access, civitdl for downloading models from CivitAI, and Hugging Face CLI for downloading from Hugging Face Hub, optimized for remote GPU deployments.

## Build System

The project uses Docker Buildx Bake for multi-target builds defined in `docker-bake.hcl`:

```bash
# Build regular image (CUDA 12.4, stable PyTorch)
docker buildx bake -f docker-bake.hcl regular

# Build dev image locally (not pushed)
docker buildx bake -f docker-bake.hcl dev

# Build RTX 5090 variant (CUDA 12.8, PyTorch Nightly)
docker buildx bake -f docker-bake.hcl rtx5090
```

Build targets:
- **regular**: Production image, tags `ghcr.io/frdrcbrg/comfy-minimal:latest`
- **dev**: Local testing image, tag `ghcr.io/frdrcbrg/comfy-minimal:dev`, output to local Docker
- **devpush**: CI dev build for pushing without overriding latest
- **rtx5090**: RTX 5090 optimized, tags `ghcr.io/frdrcbrg/comfy-minimal:latest-5090`

The `TAG` and `IMAGE_REF` variables in `docker-bake.hcl` control the tag and image reference.

## CI/CD

GitHub Actions automatically build and push images:

- **Automatic builds** (`.github/workflows/build.yml`): Triggered on push to `main` branch
  - Builds and pushes `ghcr.io/frdrcbrg/comfy-minimal:latest`
  - Builds and pushes `ghcr.io/frdrcbrg/comfy-minimal:latest-5090`

- **Release builds** (`.github/workflows/release.yml`): Triggered on version tags (e.g., `v1.0.0`)
  - Builds and pushes versioned tags: `ghcr.io/frdrcbrg/comfy-minimal:v1.0.0`
  - Also updates `latest` tags
  - Creates GitHub releases automatically

- **Dev builds** (`.github/workflows/dev.yml`): Manual workflow dispatch
  - Builds and optionally pushes dev images

All images are pushed to GitHub Container Registry (ghcr.io) and are publicly available for consumption by RunPod or other container platforms.

## Local Development

Run the dev image locally with persistence:

```bash
docker buildx bake -f docker-bake.hcl dev
docker run --rm -p 8188:8188 -p 8080:8080 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  -e CIVITAI_API_KEY=your_api_key_here \
  -e HF_TOKEN=your_hf_token_here \
  -v "$PWD/workspace":/workspace \
  ghcr.io/frdrcbrg/comfy-minimal:dev
```

Or pull and run the latest production image:

```bash
docker run --rm -p 8188:8188 -p 8080:8080 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  -e CIVITAI_API_KEY=your_api_key_here \
  -e HF_TOKEN=your_hf_token_here \
  -v "$PWD/workspace":/workspace \
  ghcr.io/frdrcbrg/comfy-minimal:latest
```

## Architecture

### Two Image Variants

1. **Regular** (`Dockerfile`, `start.sh`):
   - CUDA 12.4 with stable PyTorch from upstream requirements
   - Venv at `/workspace/runpod-slim/ComfyUI/.venv`

2. **RTX 5090** (`Dockerfile.5090`, `start.5090.sh`):
   - CUDA 12.8 with PyTorch Nightly cu128 wheels
   - Venv at `/workspace/runpod-slim/ComfyUI/.venv-cu128`
   - Masks torch-related lines in ComfyUI requirements.txt and installs explicit cu128 wheels

### Runtime Bootstrap Flow

Both `start.sh` and `start.5090.sh` execute on container start:

1. **SSH Setup**: Generates host keys, configures key-based or password auth (via `PUBLIC_KEY` env var), starts sshd
2. **Environment Export**: Propagates CUDA, RUNPOD, PATH, and other vars to `/etc/environment`, PAM config, and SSH environment
3. **FileBrowser Init**: First-run initialization on port 8080 (root: `/workspace`, default admin user)
4. **ComfyUI Setup**:
   - Clones ComfyUI and custom nodes if not present
   - Creates Python 3.12 venv using `uv` for fast installs (`UV_LINK_MODE=copy`)
   - Installs ComfyUI requirements.txt
   - Iterates through custom_nodes/* and installs requirements.txt, runs install.py/setup.py
5. **ComfyUI Launch**: Starts with fixed args `--listen 0.0.0.0 --port 8188` plus custom args from `/workspace/runpod-slim/comfyui_args.txt`

### Pre-installed Custom Nodes

- ComfyUI-Manager (ltdrdata)
- ComfyUI-KJNodes (kijai)
- Civicomfy (MoonGoblinDev)

Managed in the `CUSTOM_NODES` array in start scripts.

### Exposed Ports

- 8188: ComfyUI web interface
- 8080: FileBrowser interface
- 22: SSH access

### Built-in Tools

**civitdl** - CLI tool for batch downloading models from CivitAI, installed system-wide via pip.

API Key Configuration:
- Set the `CIVITAI_API_KEY` environment variable when starting the container
- The start script automatically exports this variable system-wide
- Once set, civitdl can access it without needing the `--api-key` flag

Usage examples:
```bash
# Download model by ID or URL to persistent storage (uses CIVITAI_API_KEY if set)
civitdl 123456 /workspace/models/checkpoints

# Or specify API key manually
civitdl --api-key YOUR_API_KEY 123456 /workspace/models/checkpoints

# Download LoRAs to persistent storage
civitdl 789012 /workspace/models/loras

# Configure additional settings (interactive)
civitconfig
```

Features:
- Downloads models with metadata and sample images
- Concurrent downloading for speed
- Smart caching to skip already-downloaded models
- API key support for private/restricted models
- Retry functionality for failed downloads
- **Auto-download on startup**: Configure models in `/workspace/civitai_models.txt` for automatic download

Auto-download configuration (`/workspace/civitai_models.txt`):
```text
# Format: MODEL_ID CATEGORY
# Example:
123456 checkpoints
789012 loras
456789 controlnet
```

The `auto_download_civitai_models()` function:
- Reads `/workspace/civitai_models.txt` on every container start
- Creates an example file if it doesn't exist
- Skips comments (`#`) and empty lines
- Parses each line as `MODEL_ID CATEGORY`
- Defaults to `checkpoints` if no category specified
- Uses civitdl's built-in caching to skip already-downloaded models
- Continues downloading even if one model fails

Repository: https://github.com/OwenTruong/civitdl

**Hugging Face CLI** - Official CLI tool for downloading models and datasets from Hugging Face Hub, installed system-wide via pip (huggingface_hub package).

Token Configuration:
- Set the `HF_TOKEN` environment variable when starting the container
- The start script automatically logs in with `huggingface-cli login` non-interactively
- Once authenticated, you can download private/gated models and upload to Hub

Usage examples:
```bash
# Download a single file to persistent storage
huggingface-cli download gpt2 config.json --local-dir /workspace/models

# Download entire model repository to persistent checkpoints
huggingface-cli download stabilityai/stable-diffusion-xl-base-1.0 --local-dir /workspace/models/checkpoints/sdxl

# Download specific revision (e.g., fp16 version) to persistent storage
huggingface-cli download runwayml/stable-diffusion-v1-5 --revision fp16 --local-dir /workspace/models/checkpoints

# Upload files to your Hub repository
huggingface-cli upload my-username/my-model ./local-folder

# Check authentication status
huggingface-cli whoami

# List cached models
huggingface-cli scan-cache
```

Features:
- Download single files or entire repositories
- Support for private and gated models (with proper authentication)
- Upload files and folders to Hugging Face Hub
- Manage local cache
- Git credential integration for seamless authentication

Get your token: https://huggingface.co/settings/tokens
Documentation: https://huggingface.co/docs/huggingface_hub/main/guides/cli

Auto-download configuration (`/workspace/huggingface_models.txt`):
```text
# Format: REPO_ID CATEGORY [REVISION]
# Example:
stabilityai/stable-diffusion-xl-base-1.0 checkpoints
runwayml/stable-diffusion-v1-5 checkpoints fp16
username/my-lora loras
```

The `auto_download_huggingface_models()` function:
- Reads `/workspace/huggingface_models.txt` on every container start
- Creates an example file if it doesn't exist
- Skips comments (`#`) and empty lines
- Parses each line as `REPO_ID CATEGORY [REVISION]`
- Defaults to `checkpoints` if no category specified
- Converts repository names with slashes to underscores (e.g., `username/model` → `username_model`)
- Downloads to `/workspace/models/{category}/{repo_name}`
- Supports optional revision parameter for specific branches/tags (e.g., `fp16`, `main`)
- Uses HF_TOKEN for authentication if configured
- Continues downloading even if one model fails

### Dependency Management

- **Python**: 3.12 system default
- **Package manager**: `uv` for fast, reproducible installs
- **Regular image**: Installs ComfyUI requirements.txt as-is
- **5090 image**: Comments out torch lines in requirements.txt, installs cu128 wheels from https://download.pytorch.org/whl/cu128

Custom node dependencies are installed idempotently on every container start to support dynamic node additions.

## Customization Points

### Adding Custom ComfyUI Arguments

Edit `/workspace/runpod-slim/comfyui_args.txt` (one arg per line, `#` for comments):

```
--max-batch-size 8
--preview-method auto
```

### Adding/Removing Custom Nodes

Edit the `CUSTOM_NODES` array in `start.sh` or `start.5090.sh`, or pre-bake them into the image by modifying the Dockerfile.

### Adding System Packages

Modify the `apt-get install` lines in the respective Dockerfile.

### Adding Python Dependencies

Extend installation blocks in the start script after venv activation. Use `uv pip install --no-cache ...` for consistency.

## Environment Variables

Recognized at runtime:
- `PUBLIC_KEY`: SSH public key for root. If not set, a random password is generated and logged
- `CIVITAI_API_KEY`: CivitAI API key for downloading models. When set, this is exported system-wide and available to civitdl
- `HF_TOKEN`: Hugging Face authentication token. When set, the CLI is automatically logged in and can access private/gated models
- `HF_HOME`: Optional. Custom location for Hugging Face cache directory
- CUDA/GPU vars (`CUDA*`, `LD_LIBRARY_PATH`, `PYTHONPATH`) are auto-propagated

## Directory Structure at Runtime

- `/workspace/models/`: **Persistent model storage** - All subdirectories are symlinked to ComfyUI's models directory
  - `checkpoints/` - Stable Diffusion checkpoints
  - `loras/` - LoRA models
  - `vae/` - VAE models
  - `embeddings/` - Textual inversion embeddings
  - `hypernetworks/` - Hypernetwork models
  - `controlnet/` - ControlNet models
  - `upscale_models/` - Upscaler models
  - `clip/` - CLIP models
  - `clip_vision/` - CLIP vision models
  - `style_models/` - Style models
  - `unet/` - UNet models
- `/workspace/workflows/`: **Persistent workflow storage** - Symlinked to ComfyUI's workflows directory
- `/workspace/civitai_models.txt`: **CivitAI auto-download configuration** - List of CivitAI model IDs to download on startup
- `/workspace/huggingface_models.txt`: **Hugging Face auto-download configuration** - List of HF repository IDs to download on startup
- `/workspace/runpod-slim/ComfyUI`: ComfyUI installation and venv
- `/workspace/runpod-slim/ComfyUI/models/`: Symlinked to `/workspace/models/` subdirectories
- `/workspace/runpod-slim/ComfyUI/user/default/workflows/`: Symlinked to `/workspace/workflows/`
- `/workspace/runpod-slim/comfyui_args.txt`: Custom startup arguments
- `/workspace/runpod-slim/filebrowser.db`: FileBrowser database
- `/workspace/runpod-slim/comfyui.log`: ComfyUI stdout/stderr

## Persistent Model Storage

The start scripts automatically set up symlinks from `/workspace/runpod-slim/ComfyUI/models/` subdirectories to `/workspace/models/` subdirectories. This means:

- **Models stored in `/workspace/models/` persist across container restarts**
- You can mount `/workspace` as a volume for persistence between container recreations
- Download models directly to `/workspace/models/{category}` and they're immediately available in ComfyUI
- When ComfyUI creates model subdirectories on first run, they're automatically backed up and replaced with symlinks

The `setup_model_symlinks()` function in start scripts:
1. Creates `/workspace/models/` and its subdirectories if they don't exist
2. Backs up any existing ComfyUI model directories (e.g., `models/checkpoints.bak`)
3. Creates symlinks from ComfyUI models directory to persistent storage
4. Handles broken symlinks gracefully

Example workflow:
```bash
# Download to persistent storage
civitdl 123456 /workspace/models/checkpoints
huggingface-cli download username/model --local-dir /workspace/models/loras

# Models are immediately available in ComfyUI via symlinks
# They survive container restarts because /workspace is typically persistent
```

## Persistent Workflow Storage

The start scripts automatically set up a symlink from `/workspace/runpod-slim/ComfyUI/user/default/workflows/` to `/workspace/workflows/`. This means:

- **Workflows saved in ComfyUI persist across container restarts**
- You can mount `/workspace` as a volume for persistence between container recreations
- Any workflows you save in ComfyUI are automatically stored in `/workspace/workflows`
- Pre-existing workflows in `/workspace/workflows` are automatically available in ComfyUI

The `setup_workflow_symlinks()` function in start scripts:
1. Creates `/workspace/workflows/` if it doesn't exist
2. Creates `ComfyUI/user/default/` directory structure if needed
3. Backs up any existing ComfyUI workflows directory (as `workflows.bak`)
4. Copies any existing workflows to persistent storage
5. Creates symlink from ComfyUI workflows directory to persistent storage
6. Handles broken symlinks gracefully

This is essential for RunPod deployments where `/workspace` is mounted as persistent storage, ensuring your workflows are never lost across container restarts.

## Development Conventions

- Keep images lean: prefer runtime installs via `uv` over baking large wheels
- Do not change ports (referenced by external RunPod templates)
- Always use Python 3.12
- When adding env vars needed downstream, export them in `export_env_vars()` in start scripts
- Shell scripts maintain `set -e`; write idempotent steps safe to re-run
- Custom node install loop checks for `requirements.txt`, `install.py`, and `setup.py`

## Troubleshooting

- **ComfyUI not reachable**: Check `/workspace/runpod-slim/comfyui.log`, verify `comfyui_args.txt` doesn't contain invalid flags
- **SSH access**: Check container logs for generated password if `PUBLIC_KEY` not provided, ensure port 22 is mapped
- **GPU issues on 5090**: Verify you're running the `-5090` tag, confirm driver compatibility with cu128 wheels
