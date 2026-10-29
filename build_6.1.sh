#!/usr/bin/env bash
# Copyright (c) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Linux 6.1+ (GKI 2.0) arm64 kernel build script.
# Toolchain: clang-r510928 (LLVM only -- no GCC cross compiler needed)

# Put this in your kernel root, edit settings below, then run:
#   chmod +x build_6.1.sh && ./build_6.1.sh
set -euo pipefail

# ---------------------------------------------------------------------------
# SETTINGS -- only part normally needing changes
# ---------------------------------------------------------------------------
DEFCONFIG="gki_defconfig"
EXTRA_CONFIGS=()
KERNEL_IMAGE="Image"           # Image | Image.gz | Image.gz-dtb
USE_OUT_DIR=1                   # 0 = build in-tree
MENUCONFIG=1                    # 0 = skip menuconfig GUI
export KBUILD_BUILD_USER="@Lycra-GX"
# Some OEM trees need extra variables. Check README_Kernel.txt/build_kernel.sh.
# export TARGET_SOC=s5e9925 PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s
# ---------------------------------------------------------------------------

KERNEL_ROOT="$(dirname "$(readlink -f "$0")")"
CLANG="${HOME}/toolchains/clang-r510928"
cd "${KERNEL_ROOT}"

info() { echo -e "\n[INFO]: $*\n"; }
die() { echo -e "\n[ERROR]: $*\n" >&2; exit 1; }

fetch() {
    [ -d "$1" ] && return 0
    info "Downloading $(basename "$1")..."
    mkdir -p "$1"
    local tar_flag=""
    case "$2" in *.xz) tar_flag="J" ;; esac
    curl -Lf --progress-bar "$2" | tar -x${tar_flag} -C "$1" --strip-components="${3:-0}" \
        || { rm -rf "$1"; die "Failed to download $2"; }
}

# CachyOS uses pacman. Package names differ from Debian/Fedora, so keep a
# native package list instead of translating RPM/DEB names.
PACMAN_PKGS=(base-devel bc bison flex pkgconf git curl tar xz zip unzip cpio rsync kmod
             perl python openssl elfutils pahole ncurses zlib libyaml lz4 zstd dtc)
RPM_PKGS=(make gcc gcc-c++ bc bison flex pkgconf git curl tar xz zip unzip cpio rsync kmod
          perl python3 openssl openssl-devel openssl-devel-engine elfutils-libelf-devel dwarves
          ncurses-devel zlib-devel libyaml-devel lz4 zstd dtc)
DEB_PKGS=(build-essential bc bison flex pkg-config git curl tar xz-utils zip unzip cpio rsync
          kmod perl python3 python-is-python3 libssl-dev libelf-dev pahole libncurses-dev
          zlib1g-dev libyaml-dev lz4 zstd device-tree-compiler)

install_deps() {
    local missing=() available=() p
    if command -v pacman &>/dev/null; then
        for p in "${PACMAN_PKGS[@]}"; do
            pacman -T "$p" &>/dev/null || missing+=("$p")
        done
        [ "${#missing[@]}" = 0 ] && return 0
        info "Installing: ${missing[*]}"
        sudo pacman -Syu --needed --noconfirm "${missing[@]}" || die "pacman failed"
    elif command -v rpm &>/dev/null; then
        for p in "${RPM_PKGS[@]}"; do
            rpm -q --whatprovides "$p" &>/dev/null || missing+=("$p")
        done
        [ "${#missing[@]}" = 0 ] && return 0
        info "Installing: ${missing[*]}"
        sudo dnf install -y --skip-unavailable "${missing[@]}" || die "dnf failed"
    elif command -v dpkg &>/dev/null; then
        for p in "${DEB_PKGS[@]}"; do
            [ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" = installed ] || missing+=("$p")
        done
        [ "${#missing[@]}" = 0 ] && return 0
        for p in "${missing[@]}"; do apt-cache show "$p" &>/dev/null && available+=("$p"); done
        [ "${#available[@]}" = 0 ] && return 0
        info "Installing: ${available[*]}"
        sudo apt update && sudo apt install -y "${available[@]}" || die "apt failed"
    else
        info "Unknown package manager -- install kernel build dependencies yourself."
    fi
}

[ -f Makefile ] && [ -d arch/arm64 ] || die "Run this from kernel source root."
install_deps
[ -f .gitmodules ] && git submodule update --init --recursive
fetch "${CLANG}" "https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r510928.tar.gz"
export PATH="${CLANG}/bin:${PATH}"
export LD_LIBRARY_PATH="${CLANG}/lib:${CLANG}/lib64:${LD_LIBRARY_PATH:-}"

BUILD_OPTIONS=(-j"$(nproc)" ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++)
if [ "${USE_OUT_DIR}" = 1 ]; then
    BUILD_OPTIONS+=(O="${KERNEL_ROOT}/out")
    BOOT_DIR="${KERNEL_ROOT}/out/arch/arm64/boot"
else
    BOOT_DIR="${KERNEL_ROOT}/arch/arm64/boot"
fi

build_kernel() {
    info "Kernel $(make kernelversion) | defconfig: ${DEFCONFIG}"
    make "${BUILD_OPTIONS[@]}" "${DEFCONFIG}" "${EXTRA_CONFIGS[@]}" || die "Failed to write .config"
    [ "${MENUCONFIG}" = 1 ] && make "${BUILD_OPTIONS[@]}" menuconfig
    make "${BUILD_OPTIONS[@]}" "${KERNEL_IMAGE}" || die "Build failed"
    mkdir -p "${KERNEL_ROOT}/build"
    cp "${BOOT_DIR}/${KERNEL_IMAGE}" "${KERNEL_ROOT}/build/"
    info "Done -> build/${KERNEL_IMAGE}"
}

build_kernel