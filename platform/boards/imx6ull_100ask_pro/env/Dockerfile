FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bc \
    bison \
    build-essential \
    cmake \
    cpio \
    curl \
    device-tree-compiler \
    diffutils \
    file \
    flex \
    gawk \
    gdb \
    gettext \
    git \
    gnupg \
    grep \
    libattr1 \
    libelf-dev \
    libglib2.0-dev \
    libgmp-dev \
    liblz4-tool \
    libmpc-dev \
    libmpfr-dev \
    libncurses-dev \
    libpixman-1-dev \
    libssl-dev \
    login \
    lzop \
    mtd-utils \
    net-tools \
    nfs-common \
    poppler-utils \
    python-is-python3 \
    python3 \
    python3 \
    python3-pip \
    python3-venv \
    qemu-system-arm \
    rsync \
    u-boot-tools \
    unzip \
    wget \
    xz-utils \
    zstd \
    7zip \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=compile
ARG UID=1000
ARG GID=1000

RUN groupadd --gid "${GID}" "${USERNAME}" \
    && useradd --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && mkdir -p /workspace \
    && chown "${USERNAME}:${USERNAME}" /workspace

USER ${USERNAME}
WORKDIR /workspace/myplatform

CMD ["/bin/bash"]
