#!/bin/bash
set -e -x

# Show system information
uname -a
CURRDIR=$(pwd)

# Determine the architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Define variables according to the architecture
if [ "$ARCH" = "x86_64" ]; then
    DEFAULT_VCPKG_TRIPLET="x64-linux"
    CCACHE_FILE="ccache-4.10.1-linux-x86_64"
elif [ "$ARCH" = "aarch64" ]; then
    DEFAULT_VCPKG_TRIPLET="aarch64-linux"
    export VCPKG_FORCE_SYSTEM_BINARIES=1
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Update the PATH variable (optional, depending on your environment)
TOOLCHAIN_PACKAGES="gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-gcc-gfortran"
TOOLCHAIN_ENABLE_CMD="source scl_source enable gcc-toolset-12"
export PATH="/usr/bin:${PATH}"

# Install common dependencies and the appropriate toolchain
yum install -y \
    ${TOOLCHAIN_PACKAGES} \
    kernel-headers \
    perl-IPC-Cmd \
    scl-utils \
    git \
    cmake3 \
    ninja-build \
    curl \
    zip \
    unzip \
    tar

# Enable the toolchain if applicable
if [ -n "$TOOLCHAIN_ENABLE_CMD" ]; then
    eval "$TOOLCHAIN_ENABLE_CMD"
fi

# Set up ccache (only for x86_64; for aarch64 this is prepared for future use)
if [ "$ARCH" = "x86_64" ]; then
    COMPILER_TOOLS_DIR="${CONTAINER_COMPILER_CACHE_DIR}/bin"
    mkdir -p "${COMPILER_TOOLS_DIR}"
    if [ ! -f "${COMPILER_TOOLS_DIR}/ccache" ]; then
        curl -sSLO "https://github.com/ccache/ccache/releases/download/v4.10.1/${CCACHE_FILE}.tar.xz"
        tar -xf "${CCACHE_FILE}.tar.xz"
        cp "${CCACHE_FILE}/ccache" "${COMPILER_TOOLS_DIR}"
    fi
    export PATH="${COMPILER_TOOLS_DIR}:${PATH}"
else
    echo "No precompiled ccache available for aarch64. The system ccache (if available) will be used."
fi

# If VCPKG_TARGET_TRIPLET is not defined, use the default based on the architecture
if [ -z "${VCPKG_TARGET_TRIPLET}" ]; then
    export VCPKG_TARGET_TRIPLET="${DEFAULT_VCPKG_TRIPLET}"
fi

# Configure vcpkg
git clone https://github.com/microsoft/vcpkg "${VCPKG_INSTALLATION_ROOT}"
cd "${VCPKG_INSTALLATION_ROOT}"
git checkout "${VCPKG_COMMIT_ID}"
./bootstrap-vcpkg.sh
./vcpkg integrate install

# Build COLMAP
cd "${CURRDIR}"
mkdir -p build && cd build
cmake3 .. -GNinja \
    -DCUDA_ENABLED=OFF \
    -DGUI_ENABLED=OFF \
    -DCGAL_ENABLED=OFF \
    -DLSD_ENABLED=OFF \
    -DCCACHE_ENABLED=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DVCPKG_TARGET_TRIPLET="${VCPKG_TARGET_TRIPLET}" \
    -DCMAKE_EXE_LINKER_FLAGS_INIT="-ldl"
ninja install

# Run ccache commands if available
if command -v ccache >/dev/null 2>&1; then
    ccache --show-stats --verbose
    ccache --evict-older-than 1d
    ccache --show-stats --verbose
else
    echo "ccache not found, skipping ccache commands."
fi
