FROM debian:bullseye AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# 安装构建工具和依赖（等价于 alpine 的 .build-dependencies）
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    binutils \
    build-essential \
    automake \
    autoconf \
    cmake \
    gcc \
    g++ \
    pkg-config \
    libtool \
    libev-dev \
    libusb-1.0-0-dev \
    linux-headers-amd64 \
    curl \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装运行期依赖（等价于 apk add 部分）
RUN apt-get update && apt-get install -y --no-install-recommends \
    udev \
    bash \
    libev4 \
    libusb-1.0-0 \
    libgcc-s1 \
    libstdc++6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /workspaces
CMD ["/bin/bash"]