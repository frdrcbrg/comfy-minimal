# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Comfy Minimal is a highly optimized Docker container (~650MB) for running ComfyUI on RunPod. It provides a complete environment with ComfyUI, FileBrowser, JupyterLab, SSH access, and civitdl for downloading models from CivitAI, optimized for remote GPU deployments.

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
docker run --rm -p 8188:8188 -p 8080:8080 -p 8888:8888 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  -e JUPYTER_PASSWORD=yourtoken \
  -e CIVITAI_API_KEY=your_api_key_here \
  -v "$PWD/workspace":/workspace \
  ghcr.io/frdrcbrg/comfy-minimal:dev
```

Or pull and run the latest production image:

```bash
docker run --rm -p 8188:8188 -p 8080:8080 -p 8888:8888 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  -e JUPYTER_PASSWORD=yourtoken \
  -e CIVITAI_API_KEY=your_api_key_here \
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
4. **JupyterLab Start**: Launches on port 8888 (root: `/workspace`, token from `JUPYTER_PASSWORD`)
5. **ComfyUI Setup**:
   - Clones ComfyUI and custom nodes if not present
   - Creates Python 3.12 venv using `uv` for fast installs (`UV_LINK_MODE=copy`)
   - Installs ComfyUI requirements.txt
   - Iterates through custom_nodes/* and installs requirements.txt, runs install.py/setup.py
6. **ComfyUI Launch**: Starts with fixed args `--listen 0.0.0.0 --port 8188` plus custom args from `/workspace/runpod-slim/comfyui_args.txt`

### Pre-installed Custom Nodes

- ComfyUI-Manager (ltdrdata)
- ComfyUI-KJNodes (kijai)
- Civicomfy (MoonGoblinDev)

Managed in the `CUSTOM_NODES` array in start scripts.

### Exposed Ports

- 8188: ComfyUI web interface
- 8080: FileBrowser interface
- 8888: JupyterLab interface
- 22: SSH access

### Built-in Tools

**civitdl** - CLI tool for batch downloading models from CivitAI, installed system-wide via pip.

API Key Configuration:
- Set the `CIVITAI_API_KEY` environment variable when starting the container
- The start script automatically exports this variable system-wide
- Once set, civitdl can access it without needing the `--api-key` flag

Usage examples:
```bash
# Download model by ID or URL to ComfyUI checkpoints (uses CIVITAI_API_KEY if set)
civitdl 123456 /workspace/runpod-slim/ComfyUI/models/checkpoints

# Or specify API key manually
civitdl --api-key YOUR_API_KEY 123456 /workspace/runpod-slim/ComfyUI/models/checkpoints

# Download LoRAs
civitdl 789012 /workspace/runpod-slim/ComfyUI/models/loras

# Configure additional settings (interactive)
civitconfig
```

Features:
- Downloads models with metadata and sample images
- Concurrent downloading for speed
- Smart caching to skip already-downloaded models
- API key support for private/restricted models
- Retry functionality for failed downloads

Repository: https://github.com/OwenTruong/civitdl

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
- `JUPYTER_PASSWORD`: JupyterLab token (no browser mode)
- `CIVITAI_API_KEY`: CivitAI API key for downloading models. When set, this is exported system-wide and available to civitdl
- CUDA/GPU vars (`CUDA*`, `LD_LIBRARY_PATH`, `PYTHONPATH`) are auto-propagated

## Directory Structure at Runtime

- `/workspace/runpod-slim/ComfyUI`: ComfyUI installation and venv
- `/workspace/runpod-slim/comfyui_args.txt`: Custom startup arguments
- `/workspace/runpod-slim/filebrowser.db`: FileBrowser database
- `/workspace/runpod-slim/comfyui.log`: ComfyUI stdout/stderr

## Development Conventions

- Keep images lean: prefer runtime installs via `uv` over baking large wheels
- Do not change ports (referenced by external RunPod templates)
- Always use Python 3.12
- When adding env vars needed downstream, export them in `export_env_vars()` in start scripts
- Shell scripts maintain `set -e`; write idempotent steps safe to re-run
- Custom node install loop checks for `requirements.txt`, `install.py`, and `setup.py`

## Troubleshooting

- **ComfyUI not reachable**: Check `/workspace/runpod-slim/comfyui.log`, verify `comfyui_args.txt` doesn't contain invalid flags
- **JupyterLab auth**: Set `JUPYTER_PASSWORD` explicitly if needed
- **SSH access**: Check container logs for generated password if `PUBLIC_KEY` not provided, ensure port 22 is mapped
- **GPU issues on 5090**: Verify you're running the `-5090` tag, confirm driver compatibility with cu128 wheels
