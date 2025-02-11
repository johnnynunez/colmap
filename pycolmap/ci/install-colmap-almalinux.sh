#!/bin/bash
set -e -x

# Mostrar información del sistema
uname -a
CURRDIR=$(pwd)

# Determinar la arquitectura
ARCH=$(uname -m)
echo "Arquitectura detectada: $ARCH"

# Definir variables según la arquitectura
if [ "$ARCH" = "x86_64" ]; then
    # Para x86_64 usamos el toolchain de gcc-toolset-12
    TOOLCHAIN_PACKAGES="gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-gcc-gfortran"
    TOOLCHAIN_ENABLE_CMD="source scl_source enable gcc-toolset-12"
    DEFAULT_VCPKG_TRIPLET="x64-linux"
    CCACHE_FILE="ccache-4.10.1-linux-x86_64"
elif [ "$ARCH" = "aarch64" ]; then
    # Para aarch64 asumimos que se utiliza el compilador del sistema
    TOOLCHAIN_PACKAGES="gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-gcc-gfortran"
    TOOLCHAIN_ENABLE_CMD="source scl_source enable gcc-toolset-12"
    DEFAULT_VCPKG_TRIPLET="aarch64-linux"
    CCACHE_FILE="ccache-4.10.1-linux-aarch64"
else
    echo "Arquitectura no soportada: $ARCH"
    exit 1
fi

# Actualizar la variable PATH (opcional, según el entorno)
export PATH="/usr/bin:${PATH}"

# Instalar las dependencias comunes y el toolchain adecuado
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

# Si es x86_64, activar el toolchain de gcc-toolset-12
if [ -n "$TOOLCHAIN_ENABLE_CMD" ]; then
    eval "$TOOLCHAIN_ENABLE_CMD"
fi

# Preparar ccache (la versión del ccache incluido en CentOS/AlmaLinux puede ser antigua)
COMPILER_TOOLS_DIR="${CONTAINER_COMPILER_CACHE_DIR}/bin"
mkdir -p "${COMPILER_TOOLS_DIR}"
if [ ! -f "${COMPILER_TOOLS_DIR}/ccache" ]; then
    # Descargar el binario correspondiente según la arquitectura
    curl -sSLO "https://github.com/ccache/ccache/releases/download/v4.10.1/${CCACHE_FILE}.tar.xz"
    tar -xf "${CCACHE_FILE}.tar.xz"
    cp "${CCACHE_FILE}/ccache" "${COMPILER_TOOLS_DIR}"
fi
export PATH="${COMPILER_TOOLS_DIR}:${PATH}"

if [ -z "${VCPKG_TARGET_TRIPLET}" ]; then
    export VCPKG_TARGET_TRIPLET="${DEFAULT_VCPKG_TRIPLET}"
fi

git clone https://github.com/microsoft/vcpkg "${VCPKG_INSTALLATION_ROOT}"
cd "${VCPKG_INSTALLATION_ROOT}"
git checkout "${VCPKG_COMMIT_ID}"
./bootstrap-vcpkg.sh
./vcpkg integrate install

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

ccache --show-stats --verbose
ccache --evict-older-than 1d
ccache --show-stats --verbose
