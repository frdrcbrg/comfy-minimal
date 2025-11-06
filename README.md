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
  - SSH access
  - civitdl for batch downloading models from CivitAI
  - Hugging Face CLI for downloading models and datasets from Hugging Face Hub
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
- `22`: SSH access

## Usage

### RunPod

Use the following Docker image in your RunPod template:

- **Regular (CUDA 12.4)**: `ghcr.io/frdrcbrg/comfy-minimal:latest`
- **RTX 5090 (CUDA 12.8)**: `ghcr.io/frdrcbrg/comfy-minimal:latest-5090`

The images are automatically built and published via GitHub Actions on every push to main.

### Local Development

```bash
docker run --rm -p 8188:8188 -p 8080:8080 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  -e CIVITAI_API_KEY=your_api_key_here \
  -e HF_TOKEN=your_hf_token_here \
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

The container includes `civitdl`, a CLI tool for batch downloading Stable Diffusion models from CivitAI.

### Setting up your CivitAI API Key

Set the `CIVITAI_API_KEY` environment variable when running the container to automatically configure your API key:

```bash
docker run -e CIVITAI_API_KEY="your_api_key_here" ...
```

In RunPod, add this as an environment variable in your template settings.

### Using civitdl

```bash
# Download a model by ID or URL (uses CIVITAI_API_KEY if set)
# Downloads to persistent storage - will survive container restarts
civitdl 123456 /workspace/models/checkpoints

# Download LoRAs
civitdl 789012 /workspace/models/loras

# Or specify API key manually
civitdl --api-key YOUR_API_KEY 123456 /workspace/models/checkpoints

# Configure additional settings interactively
civitconfig
```

Models are downloaded with their metadata and sample images. For more information, visit the [civitdl GitHub repository](https://github.com/OwenTruong/civitdl).

### Auto-Download Models on Startup

The container can automatically download models from CivitAI when it starts. Simply create a file at `/workspace/civitai_models.txt` with your model IDs:

```text
# CivitAI Model Auto-Download List
# Format: MODEL_ID CATEGORY
# Categories: checkpoints, loras, vae, embeddings, controlnet, upscale_models

123456 checkpoints
789012 loras
456789 controlnet
```

**Features:**
- One model per line in the format: `MODEL_ID CATEGORY`
- If no category is specified, defaults to `checkpoints`
- Comments start with `#`
- civitdl automatically skips already-downloaded models
- Models are downloaded to persistent storage in `/workspace/models/`

The container will automatically create an example file on first run. Edit it to add your models, and they'll be downloaded on the next container start.

## Downloading from Hugging Face

The container includes the Hugging Face CLI for downloading models and datasets from Hugging Face Hub.

### Setting up your Hugging Face Token

Set the `HF_TOKEN` environment variable when running the container to automatically authenticate:

```bash
docker run -e HF_TOKEN="your_hf_token_here" ...
```

In RunPod, add this as an environment variable in your template settings. Get your token from [https://huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).

### Using Hugging Face CLI

```bash
# Download a single file
huggingface-cli download gpt2 config.json --local-dir /workspace/models

# Download an entire model repository to persistent storage
huggingface-cli download stabilityai/stable-diffusion-xl-base-1.0 --local-dir /workspace/models/checkpoints/sdxl

# Download a specific revision
huggingface-cli download runwayml/stable-diffusion-v1-5 --revision fp16 --local-dir /workspace/models/checkpoints

# Upload files to Hub
huggingface-cli upload my-username/my-model ./local-folder

# Check authentication status
huggingface-cli whoami
```

For more information, visit the [Hugging Face CLI documentation](https://huggingface.co/docs/huggingface_hub/main/guides/cli).

### Auto-Download Models on Startup

Similar to CivitAI, the container can automatically download models from Hugging Face when it starts. Create a file at `/workspace/huggingface_models.txt`:

```text
# Hugging Face Model Auto-Download List
# Format: REPO_ID CATEGORY [REVISION]

stabilityai/stable-diffusion-xl-base-1.0 checkpoints
runwayml/stable-diffusion-v1-5 checkpoints fp16
username/my-lora loras
```

**Features:**
- Format: `REPO_ID CATEGORY [REVISION]`
- REVISION is optional (e.g., `main`, `fp16`, etc.)
- If no category is specified, defaults to `checkpoints`
- Comments start with `#`
- Models are downloaded to `/workspace/models/{category}/{repo_name}`
- Repository names with slashes (e.g., `username/model`) are converted to underscores
- huggingface-cli automatically handles caching and authentication (via `HF_TOKEN`)

The container will automatically create an example file on first run.

## Persistent Model Storage

The container automatically sets up persistent model storage at `/workspace/models` with symlinks to ComfyUI's model directories. This means:

- **All models stored in `/workspace/models` will survive container restarts**
- Models are automatically accessible to ComfyUI
- You can mount `/workspace` as a volume to persist models between containers

The following model directories are automatically symlinked:
- `checkpoints` - Stable Diffusion checkpoints
- `loras` - LoRA models
- `vae` - VAE models
- `embeddings` - Textual inversion embeddings
- `hypernetworks` - Hypernetwork models
- `controlnet` - ControlNet models
- `upscale_models` - Upscaler models
- `clip` - CLIP models
- `clip_vision` - CLIP vision models
- `style_models` - Style models
- `unet` - UNet models

Example: Download models to `/workspace/models/checkpoints` and they'll be automatically available in ComfyUI.

## Persistent Workflow Storage

The container automatically sets up persistent workflow storage at `/workspace/workflows` with a symlink to ComfyUI's workflow directory:

- **All workflows stored in `/workspace/workflows` will survive container restarts**
- Workflows are automatically accessible within ComfyUI
- You can mount `/workspace` as a volume to persist workflows between containers
- The workflow directory is symlinked to `ComfyUI/user/default/workflows`

This means any workflows you save in ComfyUI will be automatically stored in `/workspace/workflows` and persist across container restarts, which is essential for RunPod deployments where `/workspace` is mounted as persistent storage.

## Directory Structure

- `/workspace/models/`: Persistent model storage (symlinked to ComfyUI)
- `/workspace/workflows/`: Persistent workflow storage (symlinked to ComfyUI)
- `/workspace/civitai_models.txt`: CivitAI auto-download configuration (optional)
- `/workspace/huggingface_models.txt`: Hugging Face auto-download configuration (optional)
- `/workspace/runpod-slim/ComfyUI`: Main ComfyUI installation
- `/workspace/runpod-slim/comfyui_args.txt`: Custom arguments file
- `/workspace/runpod-slim/filebrowser.db`: FileBrowser database

## License

This project is licensed under the GPLv3 License.
