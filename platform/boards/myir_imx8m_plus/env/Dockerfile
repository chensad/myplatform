FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN sed -i 's|security.ubuntu.com|archive.ubuntu.com|g' /etc/apt/sources.list \
    && apt-get -o Acquire::Retries=5 update \
    && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        chrpath \
        cpio \
        curl \
        debianutils \
        diffstat \
        file \
        gawk \
        gcc-multilib \
        git \
        iputils-ping \
        libegl1-mesa \
        libsdl1.2-dev \
        libssl-dev \
        locales \
        liblz4-tool \
        m4 \
        python \
        python3 \
        python3-git \
        python3-jinja2 \
        python3-pexpect \
        python3-pip \
        rsync \
        socat \
        texinfo \
        unzip \
        vim \
        wget \
        xterm \
        xz-utils \
        zstd \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=compile
ARG UID=1000
ARG GID=1000

RUN set -eux; \
    if ! getent group "${GID}" >/dev/null; then \
        groupadd --gid "${GID}" "${USERNAME}"; \
    fi; \
    if ! getent passwd "${UID}" >/dev/null; then \
        useradd --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash "${USERNAME}"; \
    fi; \
    mkdir -p /workspace; \
    chown "${UID}:${GID}" /workspace

USER ${UID}:${GID}
WORKDIR /workspace/myplatform

CMD ["/bin/bash"]
