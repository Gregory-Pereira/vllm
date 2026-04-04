#!/bin/bash
set -euo pipefail

# vLLM Dev Container deploy script
#
# Usage:
#   ./deploy.sh build [--cuda-version 12.8.1]
#   ./deploy.sh push
#   ./deploy.sh setup-secrets
#   ./deploy.sh deploy [--namespace <ns>]
#   ./deploy.sh attach [--namespace <ns>]
#   ./deploy.sh destroy [--namespace <ns>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
CUDA_VERSION="${CUDA_VERSION:-12.8.1}"
IMAGE_NAME="${VLLM_DEV_IMAGE:-vllm-devcontainer}"
IMAGE_TAG="${VLLM_DEV_TAG:-latest}"
NAMESPACE="${VLLM_DEV_NAMESPACE:-default}"
DEPLOYMENT_NAME="vllm-devcontainer"
K8S_DIR="${SCRIPT_DIR}/kubernetes"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
vLLM Dev Container Deploy Script

Commands:
  build           Build the devcontainer image
  push            Push the image to the container registry
  setup-secrets   Create K8s secrets for git credentials (and optionally kubeconfig)
  deploy          Deploy the devcontainer to K8s
  attach          Attach to the running devcontainer pod
  destroy         Remove the devcontainer deployment and PVCs

Options:
  --cuda-version  CUDA version for build (default: ${CUDA_VERSION})
  --image         Image name (default: ${IMAGE_NAME})
  --tag           Image tag (default: ${IMAGE_TAG})
  --namespace     K8s namespace (default: ${NAMESPACE})

Environment variables:
  CUDA_VERSION          Same as --cuda-version
  VLLM_DEV_IMAGE        Same as --image
  VLLM_DEV_TAG          Same as --tag
  VLLM_DEV_NAMESPACE    Same as --namespace
EOF
    exit 1
}

log() { echo ">> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

get_pod_name() {
    kubectl get pods -n "${NAMESPACE}" -l app=${DEPLOYMENT_NAME} \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Parse global options that appear before or after the subcommand
# ---------------------------------------------------------------------------
COMMAND=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        build|push|setup-secrets|deploy|attach|destroy)
            COMMAND="$1"; shift ;;
        --cuda-version) CUDA_VERSION="$2"; shift 2 ;;
        --image)        IMAGE_NAME="$2"; shift 2 ;;
        --tag)          IMAGE_TAG="$2"; shift 2 ;;
        --namespace)    NAMESPACE="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *) err "Unknown option: $1" ;;
    esac
done

[[ -z "${COMMAND}" ]] && usage

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_build() {
    log "Building devcontainer image: ${FULL_IMAGE} (CUDA ${CUDA_VERSION})"
    docker build \
        --platform linux/amd64 \
        --build-arg CUDA_VERSION="${CUDA_VERSION}" \
        -t "${FULL_IMAGE}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        "${REPO_ROOT}"
    log "Build complete: ${FULL_IMAGE}"
}

cmd_push() {
    log "Pushing ${FULL_IMAGE}..."
    docker push "${FULL_IMAGE}"
    log "Push complete"
}

cmd_setup_secrets() {
    log "Setting up K8s secrets in namespace: ${NAMESPACE}"

    # --- Git SSH key ---
    echo ""
    echo "=== Git SSH Key ==="
    echo "This mounts your SSH key into the devcontainer for git operations."
    echo ""

    SSH_KEY_PATH=""
    for candidate in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa"; do
        if [ -f "${candidate}" ]; then
            SSH_KEY_PATH="${candidate}"
            break
        fi
    done

    if [ -z "${SSH_KEY_PATH}" ]; then
        echo "No SSH key found at ~/.ssh/id_ed25519 or ~/.ssh/id_rsa"
        read -rp "Enter path to your SSH private key (or press Enter to skip): " SSH_KEY_PATH
    else
        read -rp "Found SSH key at ${SSH_KEY_PATH}. Use this? [Y/n]: " confirm
        if [[ "${confirm}" =~ ^[Nn] ]]; then
            read -rp "Enter path to your SSH private key: " SSH_KEY_PATH
        fi
    fi

    if [ -n "${SSH_KEY_PATH}" ] && [ -f "${SSH_KEY_PATH}" ]; then
        # Delete existing secret if present
        kubectl delete secret vllm-dev-git-ssh -n "${NAMESPACE}" 2>/dev/null || true

        local create_args=("--from-file=id_ed25519=${SSH_KEY_PATH}")
        if [ -f "${SSH_KEY_PATH}.pub" ]; then
            create_args+=("--from-file=id_ed25519.pub=${SSH_KEY_PATH}.pub")
        fi

        kubectl create secret generic vllm-dev-git-ssh \
            -n "${NAMESPACE}" \
            "${create_args[@]}"
        log "Created secret: vllm-dev-git-ssh"
    else
        echo "Skipping SSH key setup"
    fi

    # --- Git config ---
    echo ""
    echo "=== Git Config ==="

    if [ -f "${HOME}/.gitconfig" ]; then
        read -rp "Mount your ~/.gitconfig into the container? [Y/n]: " confirm
        if [[ ! "${confirm}" =~ ^[Nn] ]]; then
            kubectl delete secret vllm-dev-git-config -n "${NAMESPACE}" 2>/dev/null || true
            kubectl create secret generic vllm-dev-git-config \
                -n "${NAMESPACE}" \
                --from-file=gitconfig="${HOME}/.gitconfig"
            log "Created secret: vllm-dev-git-config"
        fi
    else
        echo "No ~/.gitconfig found, skipping"
    fi

    # --- Kubeconfig (optional) ---
    echo ""
    echo "=== Kubeconfig (optional) ==="
    echo "This gives the devcontainer kubectl access. Only enable if you need it."
    read -rp "Mount your kubeconfig into the container? [y/N]: " confirm

    if [[ "${confirm}" =~ ^[Yy] ]]; then
        KUBECONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/config}"
        read -rp "Kubeconfig path [${KUBECONFIG_PATH}]: " custom_path
        KUBECONFIG_PATH="${custom_path:-${KUBECONFIG_PATH}}"

        if [ -f "${KUBECONFIG_PATH}" ]; then
            kubectl delete secret vllm-dev-kubeconfig -n "${NAMESPACE}" 2>/dev/null || true
            kubectl create secret generic vllm-dev-kubeconfig \
                -n "${NAMESPACE}" \
                --from-file=config="${KUBECONFIG_PATH}"
            log "Created secret: vllm-dev-kubeconfig"
            echo ""
            echo "IMPORTANT: Uncomment the kubeconfig volume and volumeMount in"
            echo "  ${K8S_DIR}/deployment.yaml"
            echo "to enable kubectl access inside the pod."
        else
            err "Kubeconfig not found at ${KUBECONFIG_PATH}"
        fi
    fi

    echo ""
    log "Secret setup complete"
}

cmd_deploy() {
    log "Deploying devcontainer to namespace: ${NAMESPACE}"

    # Patch the image in the deployment manifest
    kubectl apply -n "${NAMESPACE}" -f "${K8S_DIR}/deployment.yaml"

    # Update the image if it differs from the manifest default
    kubectl set image -n "${NAMESPACE}" \
        "deployment/${DEPLOYMENT_NAME}" \
        "dev=${FULL_IMAGE}"

    log "Waiting for pod to be ready..."
    kubectl rollout status -n "${NAMESPACE}" "deployment/${DEPLOYMENT_NAME}" --timeout=600s

    POD_NAME=$(get_pod_name)
    log "Dev container is running: ${POD_NAME}"
    echo ""
    echo "Attach with:"
    echo "  kubectl exec -it -n ${NAMESPACE} ${POD_NAME} -- bash"
    echo ""
    echo "Or use:"
    echo "  $0 attach --namespace ${NAMESPACE}"
}

cmd_attach() {
    POD_NAME=$(get_pod_name)
    if [ -z "${POD_NAME}" ]; then
        err "No devcontainer pod found in namespace ${NAMESPACE}. Run 'deploy' first."
    fi
    log "Attaching to ${POD_NAME}..."
    kubectl exec -it -n "${NAMESPACE}" "${POD_NAME}" -- bash
}

cmd_destroy() {
    log "Destroying devcontainer in namespace: ${NAMESPACE}"
    read -rp "This will delete the deployment and PVCs. Continue? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy] ]]; then
        echo "Cancelled"
        exit 0
    fi

    kubectl delete -n "${NAMESPACE}" -f "${K8S_DIR}/deployment.yaml" --ignore-not-found
    kubectl delete secret -n "${NAMESPACE}" vllm-dev-git-ssh --ignore-not-found
    kubectl delete secret -n "${NAMESPACE}" vllm-dev-git-config --ignore-not-found
    kubectl delete secret -n "${NAMESPACE}" vllm-dev-kubeconfig --ignore-not-found

    log "Destroyed"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${COMMAND}" in
    build)          cmd_build ;;
    push)           cmd_push ;;
    setup-secrets)  cmd_setup_secrets ;;
    deploy)         cmd_deploy ;;
    attach)         cmd_attach ;;
    destroy)        cmd_destroy ;;
esac
