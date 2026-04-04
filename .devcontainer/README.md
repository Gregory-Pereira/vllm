# vLLM Dev Container

A GPU-enabled development container for building, testing, and debugging vLLM, including C++/CUDA extensions.

Designed to be deployed as a pod in a Kubernetes cluster with GPU access.

## What's Included

- CUDA 12.8.1 devel toolkit (swappable at build time)
- Python 3.12 with all vLLM build, runtime, and test dependencies
- Build toolchain: cmake, ninja, gcc-12, ccache
- Developer tools: vim, neovim, tmux, htop, ripgrep, jq
- Editable `pip install -e .` on first start

## Quick Start

### 1. Build the image

```bash
.devcontainer/deploy.sh build

# Or with a different CUDA version:
.devcontainer/deploy.sh build --cuda-version 12.9.0

# Or with a custom image name:
.devcontainer/deploy.sh build --image quay.io/myorg/vllm-devcontainer --tag dev
```

### 2. Push to your registry

```bash
.devcontainer/deploy.sh push --image quay.io/myorg/vllm-devcontainer --tag dev
```

### 3. Set up K8s secrets

This interactively creates secrets for your git credentials (SSH key + gitconfig) and optionally your kubeconfig:

```bash
.devcontainer/deploy.sh setup-secrets --namespace my-namespace
```

**What gets created:**
- `vllm-dev-git-ssh` — your SSH private key (for git clone/push)
- `vllm-dev-git-config` — your `.gitconfig` (for name/email)
- `vllm-dev-kubeconfig` (optional) — your kubeconfig for in-pod `kubectl`

### 4. Deploy

```bash
.devcontainer/deploy.sh deploy --namespace my-namespace --image quay.io/myorg/vllm-devcontainer --tag dev
```

### 5. Attach

```bash
.devcontainer/deploy.sh attach --namespace my-namespace
```

### 6. Tear down

```bash
.devcontainer/deploy.sh destroy --namespace my-namespace
```

## Working Inside the Container

Once attached, your workflow is:

```bash
# Clone vLLM into the persistent workspace
cd /workspace
git clone git@github.com:vllm-project/vllm.git
cd vllm

# Install in editable mode (done automatically on first start if source is present)
pip install -e .

# Run tests
pytest tests/test_something.py

# Rebuild C++/CUDA extensions after modifying csrc/
pip install -e .

# ccache speeds up subsequent rebuilds (persisted in a PVC)
```

## Security Model

- **No K8s API access by default** — `automountServiceAccountToken: false` is set on the pod. The container cannot talk to the K8s API server unless you explicitly mount a kubeconfig.
- **Kubeconfig is opt-in** — uncomment the volume mount in `kubernetes/deployment.yaml` and create the secret via `deploy.sh setup-secrets`.
- **Git credentials are mounted read-only** from K8s secrets.

## Customization

### CUDA version

Override at build time:

```bash
.devcontainer/deploy.sh build --cuda-version 12.9.0
```

### GPU resources

Edit `.devcontainer/kubernetes/deployment.yaml` to change GPU count, memory, or CPU requests:

```yaml
resources:
  requests:
    nvidia.com/gpu: "2"    # Request 2 GPUs
    memory: 64Gi
```

### Environment variables

Set via the deploy script or by adding `env:` entries to the deployment manifest.

## VS Code (Local Docker)

The `devcontainer.json` also supports local use with VS Code's Dev Containers extension. This requires a local NVIDIA GPU and the NVIDIA Container Toolkit:

1. Open the repo in VS Code
2. Cmd/Ctrl+Shift+P → "Dev Containers: Reopen in Container"

## File Structure

```
.devcontainer/
├── Dockerfile              # Dev container image definition
├── devcontainer.json       # VS Code / devcontainer spec
├── deploy.sh               # Build, push, deploy lifecycle script
├── entrypoint.sh           # Container startup (credential setup, editable install)
├── kubernetes/
│   └── deployment.yaml     # K8s Deployment + PVCs
└── README.md               # This file
```
