ARG UBUNTU_VERSION="22.04"

FROM ubuntu:${UBUNTU_VERSION}

ARG USER="docker"
ARG PASSWORD="docker"
ARG USER_HOME="/home/${USER}"

ARG USE_LOCAL_SSH_KEY=false

ARG SSH_PUB_KEY
ARG SSH_PRIV_KEY
ARG AUTH_KEY

RUN if [ -z "${SSH_PUB_KEY}" ]; then echo "Error: SSH_PUB_KEY is not set" && exit 1; fi
RUN if [ -z "${SSH_PRIV_KEY}" ]; then echo "Error: SSH_PRIV_KEY is not set" && exit 1; fi
RUN if [ -z "${AUTH_KEY}" ]; then echo "Error: SSH_PRIV_KEY is not set" && exit 1; fi

SHELL ["/bin/bash", "-c"]

# Replace default servers with Korea servers
RUN sed -i 's/archive.ubuntu.com/mirror.kakao.com/g' /etc/apt/sources.list

# to skip prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# package install
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        sudo \
        openssh-server \
        gcc \
        g++ \
        git \
        vim \
        make \
        cmake \
        ninja-build \
        python3 \
        python3-pip \
        python3-dev \
        libllvm15 \
        llvm-15 \
        llvm-15-dev \
        clang-15 \
        libclang-15-dev \
        curl \
        wget \
        unzip \
        build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# add a user and make a home directory
RUN useradd -d "${USER_HOME}" -m "${USER}" && \
    echo "${USER}:${PASSWORD}" | chpasswd && \
    usermod -aG sudo "${USER}"

# setup SSH and settings
WORKDIR "${USER_HOME}/.ssh"
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    echo "${SSH_PRIV_KEY}" > id_rsa && \
    chmod 600 id_rsa && \
    ssh-keyscan github.com >> known_hosts && \
    chmod 600 known_hosts && \
    if [ "${USE_LOCAL_SSH_KEY}" = true ]; then \
      echo "${SSH_PUB_KEY}" > authorized_keys; \
    else \
      echo "${AUTH_KEY}" > authorized_keys; \
    fi && \
    chmod 600 authorized_keys && \
    chown -R ${USER}:${USER} ${USER_HOME}/.ssh && \
    chmod 700 ${USER_HOME}/.ssh

# set a default shell
RUN sed -i 's:/bin/sh:/bin/bash:g' /etc/passwd

# Setup LLVM
RUN ln -sf /usr/bin/llvm-config-15 /usr/local/bin/llvm-config

# Install Python Modules
RUN pip3 install --upgrade pip setuptools wheel && \
    pip3 install \
        numpy==1.23 \
        cython \
        pytest \
        typing_extensions \
        flatbuffers==2.0.0 \
        tflite==2.4.0

# Clone TVM v0.19
WORKDIR /opt
RUN git clone --recursive https://github.com/apache/tvm tvm && \
    pushd tvm && \
    git checkout v0.19.0 && \
    git submodule update --init --recursive && \
    popd

# Make a build directory, configure, and build
WORKDIR /opt/tvm/build
RUN cmake .. \
        -G Ninja \
        -DUSE_LLVM=/usr/bin/llvm-config-15 \
        -DUSE_CUDA=OFF \
        -DUSE_OPENCL=OFF \
        -DUSE_RPC=OFF \
        -DUSE_SORT=OFF \
        -DUSE_GRAPH_RUNTIME=ON \
        -DUSE_MICRO=ON \
        -DCMAKE_BUILD_TYPE=Release && \
    ninja

# Install Python packages to use TVM
WORKDIR /opt/tvm/python
RUN python3 -m pip install -e .

# Environment
ENV TVM_HOME=/opt/tvm
ENV PYTHONPATH=$TVM_HOME/python:${PYTHONPATH}

#### To be able to run SSH
WORKDIR "${USER_HOME}"

CMD ["/usr/sbin/sshd", "-D"]
