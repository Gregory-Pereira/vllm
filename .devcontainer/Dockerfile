# vLLM Development Container
#
# Provides a full CUDA development environment for building, testing, and
# debugging vLLM including C++/CUDA extensions in csrc/.
#
# Build:
#   docker build -t vllm-devcontainer .
#   docker build --build-arg CUDA_VERSION=12.9.0 -t vllm-devcontainer .

ARG CUDA_VERSION=12.8.1
ARG PYTHON_VERSION=3.12
ARG TARGETPLATFORM=linux/amd64
ARG BASE_IMAGE=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04

FROM --platform=${TARGETPLATFORM} ${BASE_IMAGE}

ARG CUDA_VERSION
ARG PYTHON_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System packages: compilers, dev tools, shell ergonomics
# ---------------------------------------------------------------------------
RUN apt-get update -y && apt-get install -y \
    # Build essentials
    build-essential \
    ccache \
    cmake \
    git \
    curl \
    wget \
    sudo \
    software-properties-common \
    # Developer ergonomics
    vim \
    neovim \
    tmux \
    htop \
    jq \
    less \
    ripgrep \
    fd-find \
    tree \
    unzip \
    openssh-client \
    # Needed by some vLLM dependencies
    ffmpeg \
    libsm6 \
    libxext6 \
    libgl1 \
    libibverbs-dev \
    # GCC 12 for modern C++ support
    gcc-12 \
    g++-12 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 \
       --slave /usr/bin/g++ g++ /usr/bin/g++-12 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
RUN for i in 1 2 3; do \
        add-apt-repository -y ppa:deadsnakes/ppa && break || \
        { echo "Attempt $i failed, retrying in 5s..."; sleep 5; }; \
    done \
    && apt-get update -y \
    && apt-get install -y \
       python${PYTHON_VERSION} \
       python${PYTHON_VERSION}-dev \
       python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && update-alternatives --set python3 /usr/bin/python${PYTHON_VERSION} \
    && ln -sf /usr/bin/python${PYTHON_VERSION}-config /usr/bin/python3-config \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# pip / uv
# ---------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir uv

ENV UV_HTTP_TIMEOUT=500
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_LINK_MODE=copy

# ---------------------------------------------------------------------------
# CUDA compat (same workaround as production Dockerfile)
# ---------------------------------------------------------------------------
RUN ldconfig /usr/local/cuda-$(echo ${CUDA_VERSION} | cut -d. -f1,2)/compat/

# ---------------------------------------------------------------------------
# Python dependencies: build, runtime, dev/test
# ---------------------------------------------------------------------------
ARG PYTORCH_CUDA_INDEX_BASE_URL=https://download.pytorch.org/whl
ARG TORCH_CUDA_ARCH_LIST='9.0'
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}

WORKDIR /tmp/requirements

COPY requirements/common.txt common.txt
COPY requirements/cuda.txt cuda.txt
COPY requirements/build.txt build.txt
COPY requirements/lint.txt lint.txt
COPY requirements/test.txt test.txt
COPY requirements/dev.txt dev.txt

# Install in order: runtime deps, build deps, dev/test deps
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system -r cuda.txt \
    --extra-index-url ${PYTORCH_CUDA_INDEX_BASE_URL}/cu$(echo ${CUDA_VERSION} | cut -d. -f1,2 | tr -d '.')

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system -r build.txt \
    --extra-index-url ${PYTORCH_CUDA_INDEX_BASE_URL}/cu$(echo ${CUDA_VERSION} | cut -d. -f1,2 | tr -d '.')

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system -r dev.txt \
    --extra-index-url ${PYTORCH_CUDA_INDEX_BASE_URL}/cu$(echo ${CUDA_VERSION} | cut -d. -f1,2 | tr -d '.')

# ---------------------------------------------------------------------------
# Workspace setup
# ---------------------------------------------------------------------------
WORKDIR /workspace/vllm

# Create a non-root user (optional, can be used or skipped)
ARG USERNAME=vllm-dev
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} -s /bin/bash \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Pre-create directories for credential mounts so they have correct ownership
RUN mkdir -p /home/${USERNAME}/.ssh /home/${USERNAME}/.kube \
    && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME}

# ccache config for faster rebuilds
ENV CCACHE_DIR=/workspace/.ccache
ENV PATH="/usr/lib/ccache:${PATH}"

# ---------------------------------------------------------------------------
# Entrypoint: install vLLM in editable mode, then keep container alive
# ---------------------------------------------------------------------------
COPY .devcontainer/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
