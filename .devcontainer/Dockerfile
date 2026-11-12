# The base image is Debian 13 (trixie).
#
# The reason for the constraint is the riscv-collab toolchain below: it is a
# normal x86-64 glibc program and it links against GLIBC_2.38. Debian 12 has
# glibc 2.36 and would not run it, Debian 13 has glibc 2.41.
#
# The toolchain itself is built for Ubuntu 22.04 and 24.04. The 24.04 build
# is what the CI workflow uses, see .github/workflows/main.yml.
ARG VARIANT="trixie"
FROM buildpack-deps:${VARIANT}-curl

LABEL dev.containers.features="common"

ARG VARIANT
RUN if [ "$VARIANT" = "noble" ]; then \
        if id "ubuntu" &>/dev/null; then \
            echo "Deleting user 'ubuntu'  for $VARIANT" && userdel -f -r ubuntu || echo "Failed to delete ubuntu user for $VARIANT"; \
        else \
            echo "User 'ubuntu' does not exist for $VARIANT"; \
        fi; \
    fi

# Node.js on the host is not needed for the build itself: the Node.js that
# ends up in the camera image is cross-compiled by nodejs.mk from source,
# and the npm that installs node-red is the host-nodejs package that
# Buildroot builds itself.
#
# The Node.js here is for the build scripts and for the devcontainer
# extensions. Debian trixie ships 20.19.2, which is enough. NodeSource does
# not publish a trixie repository, so the distro package is used.
ARG NODE_MAJOR=24
RUN if [ "$VARIANT" = "trixie" ]; then \
        echo "using the Debian nodejs package, NodeSource has no trixie repository"; \
    else \
        curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -; \
    fi

RUN apt update && export DEBIAN_FRONTEND=noninteractive \
    && apt -y install --no-install-recommends \
    build-essential \
    ninja-build \
    automake \
    autoconf \
    libtool \
    wget \
    curl \
    git \
    libssl-dev \
    bc \
    squashfs-tools \
    android-sdk-libsparse-utils \
    jq \
    cmake \
    tclsh \
    scons \
    parallel \
    ssh-client \
    tree \
    python3-dev \
    python3-pip \
    device-tree-compiler \
    cpio \
    fakeroot \
    flex \
    bison \
    mtools \
    gcc \
    g++ \
    libbz2-dev \
    unzip \
    ca-certificates \
    lsb-release \
    gnupg \
    sudo \
    nodejs \
    rsync \
    python-is-python3 \
    python3-jinja2 \
    python3-yaml \
    pkg-config \
    xxd \
    zip \
    gawk \
    xz-utils \
    file \
 && ln -sf /usr/bin/python3 /usr/local/bin/python || true

# The riscv64 musl toolchain from the riscv-collab project. It is needed
# for the cross-compiled Node.js: Node.js 24 and later require a C++20
# compiler, and the in-tree cvitec toolchain is GCC 10.2.
#
# external/scripts/setup-node26-toolchain.sh swaps the runtime libraries of
# the cvitec sysroot for the ones from this toolchain, and it expects the
# toolchain at this path. The CI workflow does the same, see
# .github/workflows/main.yml.
ARG RISCV_TOOLCHAIN_URL=https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2026.10.21/riscv64-musl-ubuntu-24.04-gcc.tar.xz
RUN mkdir -p /opt/toolchains/riscv64-musl \
    && curl -fsSL --retry 5 -o /tmp/riscv64-musl.tar.xz "${RISCV_TOOLCHAIN_URL}" \
    && tar xJf /tmp/riscv64-musl.tar.xz -C /opt/toolchains/riscv64-musl --strip-components=1 \
    && rm -f /tmp/riscv64-musl.tar.xz \
    && /opt/toolchains/riscv64-musl/bin/riscv64-unknown-linux-musl-gcc --version | head -1

ENV TC_ROOT=/opt/toolchains/riscv64-musl
