#!/bin/bash
set -e

echo "=== vLLM Dev Container ==="

# ---------------------------------------------------------------------------
# Git credentials: configure SSH if keys are mounted
# ---------------------------------------------------------------------------
if [ -f /home/vllm-dev/.ssh/id_ed25519 ] || [ -f /home/vllm-dev/.ssh/id_rsa ]; then
    echo ">> SSH key detected, configuring git SSH..."
    chmod 700 /home/vllm-dev/.ssh
    chmod 600 /home/vllm-dev/.ssh/id_* 2>/dev/null || true
    chmod 644 /home/vllm-dev/.ssh/*.pub 2>/dev/null || true

    # Add common git hosts to known_hosts if not already present
    if [ ! -f /home/vllm-dev/.ssh/known_hosts ]; then
        ssh-keyscan -t ed25519,rsa github.com gitlab.com 2>/dev/null > /home/vllm-dev/.ssh/known_hosts
    fi
fi

# ---------------------------------------------------------------------------
# Kubeconfig: set KUBECONFIG if mounted
# ---------------------------------------------------------------------------
if [ -f /home/vllm-dev/.kube/config ]; then
    echo ">> Kubeconfig detected at /home/vllm-dev/.kube/config"
    export KUBECONFIG=/home/vllm-dev/.kube/config
fi

# ---------------------------------------------------------------------------
# Editable install of vLLM (if source is present and not already installed)
# ---------------------------------------------------------------------------
if [ -f /workspace/vllm/setup.py ] && ! python3 -c "import vllm" 2>/dev/null; then
    echo ">> Installing vLLM in editable mode (this may take a while on first run)..."
    cd /workspace/vllm
    pip install -e . 2>&1 | tail -5
    echo ">> vLLM installed successfully"
fi

echo "=== Dev container ready ==="
echo "CUDA version: $(nvcc --version 2>/dev/null | grep release | awk '{print $6}' | cut -c2-)"
echo "Python: $(python3 --version)"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "No GPU detected (will be available when deployed to K8s with GPU)"

# Keep the container running
exec sleep infinity
