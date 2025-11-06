variable "TAG" {
  default = "latest"
}

variable "IMAGE_REF" {
  default = "ghcr.io/frdrcbrg/comfy-minimal"
}

# Common settings for all targets
target "common" {
  context = "."
  platforms = ["linux/amd64"]
  args = {
    BUILDKIT_INLINE_CACHE = "1"
  }
}

# Regular ComfyUI image (CUDA 12.4)
target "regular" {
  inherits = ["common"]
  dockerfile = "Dockerfile"
  tags = [
    "${IMAGE_REF}:${TAG}",
    "${IMAGE_REF}:latest",
  ]
}

# Dev image for local testing
target "dev" {
  inherits = ["common"]
  dockerfile = "Dockerfile"
  tags = ["${IMAGE_REF}:dev"]
  output = ["type=docker"]
}

# Dev push targets (for CI pushing dev tags, without overriding latest)
target "devpush" {
  inherits = ["common"]
  dockerfile = "Dockerfile"
  tags = ["${IMAGE_REF}:dev"]
}

target "devpush5090" {
  inherits = ["common"]
  dockerfile = "Dockerfile.5090"
  tags = ["${IMAGE_REF}:dev-5090"]
}

# RTX 5090 optimized image (CUDA 12.8 + latest PyTorch build)
target "rtx5090" {
  inherits = ["common"]
  dockerfile = "Dockerfile.5090"
  args = {
    START_SCRIPT = "start.5090.sh"
  }
  tags = [
    "${IMAGE_REF}:${TAG}-5090",
    "${IMAGE_REF}:latest-5090",
  ]
}
