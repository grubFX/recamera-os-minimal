# The base image is Debian 13 (trixie).
#
# The reason for the constraint is the host toolchain. The packages are
# cross-compiled, but the host tools that Buildroot builds itself are
# compiled against the host libc. util-linux 2.41.3 and fakeroot 1.37.2 need
# a current glibc: Debian 12 has glibc 2.36 and does not build them, Debian 13
# has glibc 2.41.
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

# Node.js on the host is only needed for the devcontainer extensions and for
# the build scripts. It is not in the camera image.
#
# Debian trixie ships 20.19.2, which is enough. NodeSource does not publish
# a trixie repository, so the distro package is used.
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
    e2fsprogs \
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

# The prebuilt make_ext4fs in build/tools/common/prebuild needs libpcre.so.3
# (PCRE1). Debian 13 dropped PCRE1 from the archive, so the library is taken
# from the Debian package pool. Without it the "data" partition cannot be
# packed.
ARG PCRE3_DEB="http://ftp.debian.org/debian/pool/main/p/pcre3/libpcre3_8.39-15_amd64.deb"
RUN if ! [ -e /usr/lib/x86_64-linux-gnu/libpcre.so.3 ]; then \
        curl -fsSL -o /tmp/libpcre3.deb "${PCRE3_DEB}" \
        && dpkg -i /tmp/libpcre3.deb \
        && rm -f /tmp/libpcre3.deb; \
    fi

# The riscv64 musl toolchain from the riscv-collab project is not needed any
# more. It was there for the cross-compiled Node.js: Node.js 24 and later
# require a C++20 compiler, and the in-tree cvitec toolchain is GCC 10.2.
# Node.js is not in the image.
