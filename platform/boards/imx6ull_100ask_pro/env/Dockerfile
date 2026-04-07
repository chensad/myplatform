FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bc \
    bison \
    build-essential \
    ccache \
    cmake \
    cpio \
    file \
    flex \
    gawk \
    gcc-multilib \
    git \
    libncurses5-dev \
    libssl-dev \
    locales \
    python3 \
    python3-pip \
    rsync \
    sudo \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

WORKDIR /workspace/myplatform
