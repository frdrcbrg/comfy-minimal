# Comfy Minimal

A compact and optimized Docker container designed as an easy-to-use RunPod template for ComfyUI. Images are highly optimized for size, only ~650MB while including all features!

## Why Comfy Minimal?

- Purpose-built for RunPod deployments
- Ultra-compact: Only ~650MB image size (compared to multi-GB alternatives)
- Zero configuration needed: Works out of the box
- Includes all essential tools for remote work

## Features

- Two optimized variants:
  - Regular: CUDA 12.4 with stable PyTorch
  - RTX 5090: CUDA 12.8 with PyTorch Nightly (optimized for latest NVIDIA GPUs)
- Built-in tools:
  - FileBrowser for easy file management (port 8080)
  - JupyterLab workspace (port 8048)
  - SSH access
  - civitdl for batch downloading models from CivitAI
- Pre-installed custom nodes:
  - ComfyUI-Manager
  - ComfyUI-Crystools
  - ComfyUI-KJNodes
- Performance optimizations:
  - UV package installer for faster dependency installation
  - NVENC support in FFmpeg
  - Optimized CUDA configurations

## Ports

- `8188`: ComfyUI web interface
- `8080`: FileBrowser interface
- `8048`: JupyterLab interface
- `22`: SSH access

## Usage

### RunPod

Use the following Docker image in your RunPod template:

- **Regular (CUDA 12.4)**: `ghcr.io/frdrcbrg/comfy-minimal:latest`
- **RTX 5090 (CUDA 12.8)**: `ghcr.io/frdrcbrg/comfy-minimal:latest-5090`

The images are automatically built and published via GitHub Actions on every push to main.

### Local Development

```bash
docker run --rm -p 8188:8188 -p 8080:8080 -p 8888:8888 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  -e JUPYTER_PASSWORD=yourtoken \
  -v "$PWD/workspace":/workspace \
  ghcr.io/frdrcbrg/comfy-minimal:latest
```

## Custom Arguments

You can customize ComfyUI startup arguments by editing `/workspace/runpod-slim/comfyui_args.txt`. Add one argument per line:
```
--max-batch-size 8
--preview-method auto
```

## Downloading Models from CivitAI

The container includes `civitdl`, a CLI tool for batch downloading Stable Diffusion models from CivitAI:

```bash
# Download a model by ID or URL
civitdl 123456 /workspace/runpod-slim/ComfyUI/models/checkpoints

# Download with API key (for restricted models)
civitdl --api-key YOUR_API_KEY 123456 /workspace/runpod-slim/ComfyUI/models/checkpoints

# Configure default settings
civitconfig
```

Models are downloaded with their metadata and sample images. For more information, visit the [civitdl GitHub repository](https://github.com/OwenTruong/civitdl).

## Directory Structure

- `/workspace/runpod-slim/ComfyUI`: Main ComfyUI installation
- `/workspace/runpod-slim/comfyui_args.txt`: Custom arguments file
- `/workspace/runpod-slim/filebrowser.db`: FileBrowser database

## License

This project is licensed under the GPLv3 License.

