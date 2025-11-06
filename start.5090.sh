#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv-cu128"
FILEBROWSER_CONFIG="/root/.config/filebrowser/config.json"
DB_FILE="/workspace/runpod-slim/filebrowser.db"

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                  #
# ---------------------------------------------------------------------------- #

# Setup SSH with optional key or random password
setup_ssh() {
    mkdir -p ~/.ssh
    
    # Generate host keys if they don't exist
    for type in rsa dsa ecdsa ed25519; do
        if [ ! -f "/etc/ssh/ssh_host_${type}_key" ]; then
            ssh-keygen -t ${type} -f "/etc/ssh/ssh_host_${type}_key" -q -N ''
            echo "${type^^} key fingerprint:"
            ssh-keygen -lf "/etc/ssh/ssh_host_${type}_key.pub"
        fi
    done

    # If PUBLIC_KEY is provided, use it
    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        # Generate random password if no public key
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "Generated random SSH password for root: ${RANDOM_PASS}"
    fi

    # Configure SSH to preserve environment variables
    echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config

    # Start SSH service
    /usr/sbin/sshd
}

# Export environment variables
export_env_vars() {
    echo "Exporting environment variables..."
    
    # Create environment files
    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"
    
    # Backup original files
    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true
    
    # Clear files
    > "$ENV_FILE"
    > "$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    > "$SSH_ENV_DIR"
    
    # Export to multiple locations for maximum compatibility
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^CIVITAI_API_KEY|^HF_TOKEN|^HF_HOME' | while read -r line; do
        # Get variable name and value
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)
        
        # Add to /etc/environment (system-wide)
        echo "$name=\"$value\"" >> "$ENV_FILE"
        
        # Add to PAM environment
        echo "$name DEFAULT=\"$value\"" >> "$PAM_ENV_FILE"
        
        # Add to SSH environment file
        echo "$name=\"$value\"" >> "$SSH_ENV_DIR"
        
        # Add to current shell
        echo "export $name=\"$value\"" >> /etc/rp_environment
    done
    
    # Add sourcing to shell startup files
    echo 'source /etc/rp_environment' >> ~/.bashrc
    echo 'source /etc/rp_environment' >> /etc/bash.bashrc
    
    # Set permissions
    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

# Start Jupyter Lab server for remote access
start_jupyter() {
    mkdir -p /workspace
    echo "Starting Jupyter Lab on port 8888..."
    nohup jupyter lab \
        --allow-root \
        --no-browser \
        --port=8888 \
        --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --FileContentsManager.preferred_dir=/workspace \
        --ServerApp.root_dir=/workspace \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --IdentityProvider.token="${JUPYTER_PASSWORD:-}" \
        --ServerApp.allow_origin=* &> /jupyter.log &
    echo "Jupyter Lab started"
}

# Configure civitdl with API key if provided
configure_civitdl() {
    if [[ -n "$CIVITAI_API_KEY" ]]; then
        echo "Configuring civitdl with provided API key..."
        export CIVITAI_API_KEY="$CIVITAI_API_KEY"
        echo "CIVITAI_API_KEY has been set and will be available for civitdl"
    fi
}

# Configure Hugging Face CLI with token if provided
configure_huggingface() {
    if [[ -n "$HF_TOKEN" ]]; then
        echo "Configuring Hugging Face CLI with provided token..."
        export HF_TOKEN="$HF_TOKEN"
        # Login non-interactively
        huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential 2>/dev/null || true
        echo "HF_TOKEN has been set and huggingface-cli has been configured"
    fi
}

# Setup persistent model storage with symlinks
setup_model_symlinks() {
    echo "Setting up persistent model storage..."

    # Create persistent models directory
    mkdir -p /workspace/models

    # ComfyUI models directory
    MODELS_DIR="$COMFYUI_DIR/models"

    # Common model subdirectories in ComfyUI
    MODEL_SUBDIRS=(
        "checkpoints"
        "loras"
        "vae"
        "embeddings"
        "hypernetworks"
        "controlnet"
        "upscale_models"
        "clip"
        "clip_vision"
        "style_models"
        "unet"
    )

    # Create persistent directories and symlink them
    for subdir in "${MODEL_SUBDIRS[@]}"; do
        PERSISTENT_DIR="/workspace/models/$subdir"
        COMFYUI_MODEL_DIR="$MODELS_DIR/$subdir"

        # Create persistent directory if it doesn't exist
        mkdir -p "$PERSISTENT_DIR"

        # If ComfyUI model dir exists and is not a symlink, back it up
        if [ -d "$COMFYUI_MODEL_DIR" ] && [ ! -L "$COMFYUI_MODEL_DIR" ]; then
            echo "Backing up existing $subdir directory..."
            mv "$COMFYUI_MODEL_DIR" "${COMFYUI_MODEL_DIR}.bak"
        fi

        # Remove if it's a broken symlink
        if [ -L "$COMFYUI_MODEL_DIR" ] && [ ! -e "$COMFYUI_MODEL_DIR" ]; then
            rm "$COMFYUI_MODEL_DIR"
        fi

        # Create symlink if it doesn't exist
        if [ ! -e "$COMFYUI_MODEL_DIR" ]; then
            ln -s "$PERSISTENT_DIR" "$COMFYUI_MODEL_DIR"
            echo "Created symlink: $COMFYUI_MODEL_DIR -> $PERSISTENT_DIR"
        fi
    done

    echo "Model storage symlinks configured successfully"
}

# Setup persistent workflow storage
setup_workflow_symlinks() {
    echo "Setting up persistent workflow storage..."

    PERSISTENT_WORKFLOWS="/workspace/workflows"
    COMFYUI_WORKFLOWS="$COMFYUI_DIR/user/default/workflows"

    # Create persistent workflows directory if it doesn't exist
    mkdir -p "$PERSISTENT_WORKFLOWS"

    # Create user/default directory structure if it doesn't exist
    mkdir -p "$COMFYUI_DIR/user/default"

    # Handle existing workflows directory
    if [ -d "$COMFYUI_WORKFLOWS" ] && [ ! -L "$COMFYUI_WORKFLOWS" ]; then
        echo "Backing up existing workflows directory..."
        mv "$COMFYUI_WORKFLOWS" "${COMFYUI_WORKFLOWS}.bak"
        # Copy any existing workflows to persistent storage
        if [ -d "${COMFYUI_WORKFLOWS}.bak" ]; then
            cp -r "${COMFYUI_WORKFLOWS}.bak"/* "$PERSISTENT_WORKFLOWS/" 2>/dev/null || true
        fi
    fi

    # Remove broken symlink if it exists
    if [ -L "$COMFYUI_WORKFLOWS" ] && [ ! -e "$COMFYUI_WORKFLOWS" ]; then
        rm "$COMFYUI_WORKFLOWS"
    fi

    # Create symlink if it doesn't exist
    if [ ! -e "$COMFYUI_WORKFLOWS" ]; then
        ln -s "$PERSISTENT_WORKFLOWS" "$COMFYUI_WORKFLOWS"
        echo "Created symlink: $COMFYUI_WORKFLOWS -> $PERSISTENT_WORKFLOWS"
    fi

    echo "Workflow storage symlink configured successfully"
}

# Auto-download models from CivitAI based on model list
auto_download_civitai_models() {
    MODELS_LIST="/workspace/civitai_models.txt"

    # Create example file if it doesn't exist
    if [ ! -f "$MODELS_LIST" ]; then
        echo "Creating example CivitAI models list at $MODELS_LIST"
        cat > "$MODELS_LIST" << 'MODELLIST'
# CivitAI Model Auto-Download List
# Add one model per line in the format: MODEL_ID CATEGORY
# Categories: checkpoints, loras, vae, embeddings, controlnet, upscale_models
# Example:
# 123456 checkpoints
# 789012 loras

MODELLIST
        return
    fi

    # Check if file has content (excluding comments and empty lines)
    if ! grep -v '^#' "$MODELS_LIST" | grep -v '^[[:space:]]*$' | grep -q .; then
        echo "No models configured in $MODELS_LIST, skipping auto-download"
        return
    fi

    echo "Auto-downloading CivitAI models from $MODELS_LIST..."

    # Read the file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue

        # Parse model ID and category
        read -r model_id category <<< "$line"

        # Default to checkpoints if no category specified
        if [ -z "$category" ]; then
            category="checkpoints"
        fi

        # Validate model ID is a number
        if ! [[ "$model_id" =~ ^[0-9]+$ ]]; then
            echo "Skipping invalid model ID: $model_id"
            continue
        fi

        # Download the model
        echo "Downloading CivitAI model $model_id to /workspace/models/$category..."
        civitdl "$model_id" "/workspace/models/$category" || echo "Failed to download model $model_id"

    done < "$MODELS_LIST"

    echo "CivitAI auto-download complete"
}

# Auto-download models from Hugging Face based on model list
auto_download_huggingface_models() {
    MODELS_LIST="/workspace/huggingface_models.txt"

    # Create example file if it doesn't exist
    if [ ! -f "$MODELS_LIST" ]; then
        echo "Creating example Hugging Face models list at $MODELS_LIST"
        cat > "$MODELS_LIST" << 'MODELLIST'
# Hugging Face Model Auto-Download List
# Add one model per line in the format: REPO_ID CATEGORY [REVISION]
# Categories: checkpoints, loras, vae, embeddings, controlnet, upscale_models
# REVISION is optional (e.g., main, fp16, etc.)
# Example:
# stabilityai/stable-diffusion-xl-base-1.0 checkpoints
# runwayml/stable-diffusion-v1-5 checkpoints fp16
# username/my-lora loras

MODELLIST
        return
    fi

    # Check if file has content (excluding comments and empty lines)
    if ! grep -v '^#' "$MODELS_LIST" | grep -v '^[[:space:]]*$' | grep -q .; then
        echo "No models configured in $MODELS_LIST, skipping auto-download"
        return
    fi

    echo "Auto-downloading Hugging Face models from $MODELS_LIST..."

    # Read the file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue

        # Parse repo ID, category, and optional revision
        read -r repo_id category revision <<< "$line"

        # Validate repo_id is not empty
        if [ -z "$repo_id" ]; then
            echo "Skipping empty repo ID"
            continue
        fi

        # Default to checkpoints if no category specified
        if [ -z "$category" ]; then
            category="checkpoints"
        fi

        # Build download directory path
        # Replace slashes in repo_id with underscores for directory name
        repo_dir=$(echo "$repo_id" | tr '/' '_')
        download_path="/workspace/models/$category/$repo_dir"

        # Build huggingface-cli command
        echo "Downloading Hugging Face model $repo_id to $download_path..."

        if [ -n "$revision" ]; then
            # Download with specific revision
            huggingface-cli download "$repo_id" --revision "$revision" --local-dir "$download_path" || echo "Failed to download model $repo_id (revision: $revision)"
        else
            # Download default revision
            huggingface-cli download "$repo_id" --local-dir "$download_path" || echo "Failed to download model $repo_id"
        fi

    done < "$MODELS_LIST"

    echo "Hugging Face auto-download complete"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Setup environment
setup_ssh
export_env_vars
configure_civitdl
configure_huggingface

# Initialize FileBrowser if not already done
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing FileBrowser..."
    filebrowser config init
    filebrowser config set --address 0.0.0.0
    filebrowser config set --port 8080
    filebrowser config set --root /workspace
    filebrowser config set --auth.method=json
    filebrowser users add admin adminadmin12 --perm.admin
else
    echo "Using existing FileBrowser configuration..."
fi

# Start FileBrowser
echo "Starting FileBrowser on port 8080..."
nohup filebrowser &> /filebrowser.log &

start_jupyter

# Create default comfyui_args.txt if it doesn't exist
ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
if [ ! -f "$ARGS_FILE" ]; then
    echo "# Add your custom ComfyUI arguments here (one per line)" > "$ARGS_FILE"
    echo "Created empty ComfyUI arguments file at $ARGS_FILE"
fi

# Setup ComfyUI if needed
if [ ! -d "$COMFYUI_DIR" ] || [ ! -d "$VENV_DIR" ]; then
    echo "First time setup: Installing ComfyUI and dependencies..."
    
    # Clone ComfyUI if not present
    if [ ! -d "$COMFYUI_DIR" ]; then
        cd /workspace/runpod-slim
        git clone https://github.com/comfyanonymous/ComfyUI.git
        
        # Comment out torch packages from requirements.txt
        cd ComfyUI
        sed -i 's/^torch/#torch/' requirements.txt
        sed -i 's/^torchvision/#torchvision/' requirements.txt
        sed -i 's/^torchaudio/#torchaudio/' requirements.txt
        sed -i 's/^torchsde/#torchsde/' requirements.txt
    fi
    
    # Install ComfyUI-Manager if not present
    if [ ! -d "$COMFYUI_DIR/custom_nodes/ComfyUI-Manager" ]; then
        echo "Installing ComfyUI-Manager..."
        mkdir -p "$COMFYUI_DIR/custom_nodes"
        cd "$COMFYUI_DIR/custom_nodes"
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    fi

    # Install additional custom nodes
    CUSTOM_NODES=(
        "https://github.com/kijai/ComfyUI-KJNodes"
        "https://github.com/MoonGoblinDev/Civicomfy"
    )

    for repo in "${CUSTOM_NODES[@]}"; do
        repo_name=$(basename "$repo")
        if [ ! -d "$COMFYUI_DIR/custom_nodes/$repo_name" ]; then
            echo "Installing $repo_name..."
            cd "$COMFYUI_DIR/custom_nodes"
            git clone "$repo"
        fi
    done
    
    # Create and setup virtual environment if not present
    if [ ! -d "$VENV_DIR" ]; then
        cd $COMFYUI_DIR
        python3.12 -m venv $VENV_DIR
        source $VENV_DIR/bin/activate
        
        # Use pip first to install uv
        pip install -U pip
        pip install uv
        
        # Configure uv to use copy instead of hardlinks
        export UV_LINK_MODE=copy
        
        # Install the requirements
        uv pip install --no-cache -r requirements.txt
        
        # Install PyTorch (CUDA 12.8 build)
        uv pip install --no-cache torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
        
        # Install dependencies for custom nodes
        echo "Installing/updating dependencies for custom nodes..."
        uv pip install --no-cache GitPython numpy pillow opencv-python torchsde  # Common dependencies
        
        # Install dependencies for all custom nodes
        cd "$COMFYUI_DIR/custom_nodes"
        for node_dir in */; do
            if [ -d "$node_dir" ]; then
                echo "Checking dependencies for $node_dir..."
                cd "$COMFYUI_DIR/custom_nodes/$node_dir"
                
                # Check for requirements.txt
                if [ -f "requirements.txt" ]; then
                    echo "Installing requirements.txt for $node_dir"
                    uv pip install --no-cache -r requirements.txt
                fi
                
                # Check for install.py
                if [ -f "install.py" ]; then
                    echo "Running install.py for $node_dir"
                    python install.py
                fi
                
                # Check for setup.py
                if [ -f "setup.py" ]; then
                    echo "Running setup.py for $node_dir"
                    uv pip install --no-cache -e .
                fi
            fi
        done
    fi
else
    # Just activate the existing venv
    source $VENV_DIR/bin/activate
    
    # Always install/update dependencies for custom nodes
    echo "Installing/updating dependencies for custom nodes..."
    uv pip install --no-cache GitPython numpy pillow  # Common dependencies
    
    # Install dependencies for all custom nodes
    cd "$COMFYUI_DIR/custom_nodes"
    for node_dir in */; do
        if [ -d "$node_dir" ]; then
            echo "Checking dependencies for $node_dir..."
            cd "$COMFYUI_DIR/custom_nodes/$node_dir"
            
            # Check for requirements.txt
            if [ -f "requirements.txt" ]; then
                echo "Installing requirements.txt for $node_dir"
                uv pip install --no-cache -r requirements.txt
            fi
            
            # Check for install.py
            if [ -f "install.py" ]; then
                echo "Running install.py for $node_dir"
                python install.py
            fi
            
            # Check for setup.py
            if [ -f "setup.py" ]; then
                echo "Running setup.py for $node_dir"
                uv pip install --no-cache -e .
            fi
        fi
    done
fi

# Setup persistent model storage with symlinks
setup_model_symlinks

# Setup persistent workflow storage with symlinks
setup_workflow_symlinks

# Auto-download CivitAI models if configured
auto_download_civitai_models

# Auto-download Hugging Face models if configured
auto_download_huggingface_models

# Start ComfyUI with custom arguments if provided
cd $COMFYUI_DIR
FIXED_ARGS="--listen 0.0.0.0 --port 8188"
if [ -s "$ARGS_FILE" ]; then
    # File exists and is not empty, combine fixed args with custom args
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')
    if [ ! -z "$CUSTOM_ARGS" ]; then
        echo "Starting ComfyUI with additional arguments: $CUSTOM_ARGS"
        nohup python main.py $FIXED_ARGS $CUSTOM_ARGS &> /workspace/runpod-slim/comfyui.log &
    else
        echo "Starting ComfyUI with default arguments"
        nohup python main.py $FIXED_ARGS &> /workspace/runpod-slim/comfyui.log &
    fi
else
    # File is empty, use only fixed args
    echo "Starting ComfyUI with default arguments"
    nohup python main.py $FIXED_ARGS &> /workspace/runpod-slim/comfyui.log &
fi

# Tail the log file
tail -f /workspace/runpod-slim/comfyui.log
