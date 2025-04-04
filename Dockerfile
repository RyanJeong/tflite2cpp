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
      build-essential \
      cmake \
      git \
      wget \
      curl \
      unzip \
      vim \
      python3 \
      python3-pip \
      python3-setuptools \
      python3-dev \
      ninja-build && \
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

# Upgrade pip and install required Python packages
RUN python3 -m pip install --upgrade pip
RUN pip3 install numpy scipy decorator attrs tornado psutil \
    typing-extensions cloudpickle pytest jinja2 onnx onnxruntime tflite-runtime

# Install LLVM and Clang
WORKDIR /usr/local
RUN git clone --depth=1 --branch llvmorg-16.0.0 https://github.com/llvm/llvm-project.git \
    && mkdir -p llvm-project/build \
    && cd llvm-project/build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_PROJECTS="clang" \
        -G "Unix Makefiles" ../llvm \
    && make -j$(nproc) \
    && make install

# Install Cython
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && pip3 install --no-cache-dir Cython

# Install TVM
WORKDIR /opt
RUN git clone --recursive https://github.com/apache/tvm tvm \
    && cd tvm \
    && mkdir build \
    && cp cmake/config.cmake build \
    && cd build \
    && cmake .. \
        -DUSE_LLVM=/usr/local/bin/llvm-config \
        -DUSE_RELAY=ON \
        -DUSE_GRAPH_EXECUTOR=ON \
        -DUSE_RELAY_DEBUG=ON \
    && make -j$(nproc)

# Install Python TVM packages
WORKDIR /opt/tvm/python
RUN pip3 install --no-cache-dir -e .

# Set environment variables
ENV TVM_HOME=/opt/tvm
ENV PYTHONPATH=$TVM_HOME/python:$PYTHONPATH
ENV PATH=$TVM_HOME/build:$PATH
ENV LD_LIBRARY_PATH=/opt/tvm/build:$LD_LIBRARY_PATH

#### To be able to run SSH
WORKDIR "${USER_HOME}"

CMD ["/usr/sbin/sshd", "-D"]
