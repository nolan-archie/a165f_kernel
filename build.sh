#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIREMENTS_FILE="${SCRIPT_DIR}/.requirements"
TOOLCHAIN_MARKER="${SCRIPT_DIR}/.toolchain_installed"
TOOLCHAIN_URL="https://github.com/ravindu644/android_kernel_a165f/releases/download/toolchain/toolchain.tar.gz"
TOOLCHAIN_ARCHIVE="toolchain.tar.gz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
    if check_command pacman; then
        echo "pacman"
    elif check_command apt; then
        echo "apt"
    elif check_command dnf; then
        echo "dnf"
    elif check_command zypper; then
        echo "zypper"
    else
        die "Unsupported package manager"
    fi
}

install_dependencies() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    log_info "Package manager: ${pkg_manager}"
    
    case "${pkg_manager}" in
        pacman)
            local arch_packages=(
                "base-devel"
                "rsync"
                "git"
                "tar"
                "gzip"
                "curl"
                "wget"
                "bc"
                "cpio"
                "flex"
                "bison"
                "zip"
                "unzip"
                "openssl"
                "dtc"
            )
            
            log_info "Installing dependencies"
            sudo pacman -S --needed --noconfirm "${arch_packages[@]}" || die "Dependency install failed"
            ;;
            
        apt)
            local debian_packages=(
                "build-essential"
                "rsync"
                "python3"
                "git"
                "tar"
                "gzip"
                "curl"
                "wget"
                "bc"
                "cpio"
                "flex"
                "bison"
                "zip"
                "unzip"
                "libncurses-dev"
                "libssl-dev"
                "device-tree-compiler"
            )
            
            log_info "Installing dependencies"
            sudo apt update || die "Package update failed"
            sudo apt install -y "${debian_packages[@]}" || die "Dependency install failed"
            ;;
            
        dnf)
            log_info "Installing dependencies"
            sudo dnf install -y gcc gcc-c++ make rsync python3 git tar gzip curl wget bc cpio flex bison zip unzip openssl-devel dtc || die "Dependency install failed"
            ;;
            
        *)
            die "Package manager not supported: ${pkg_manager}"
            ;;
    esac
    
    log_success "Dependencies installed"
}

check_and_install_requirements() {
    if [[ -f "${REQUIREMENTS_FILE}" ]]; then
        log_info "Requirements already satisfied"
        return 0
    fi
    
    log_info "Installing build requirements"
    install_dependencies
    
    touch "${REQUIREMENTS_FILE}" 2>/dev/null || true
    log_success "Requirements satisfied"
}

download_toolchain() {
    local temp_dir
    temp_dir=$(mktemp -d) || die "Cannot create temp directory"
    
    trap "rm -rf '${temp_dir}'" EXIT
    
    log_info "Downloading toolchain"
    
    curl -L --progress-bar -o "${temp_dir}/${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}" || die "Toolchain download failed"
    
    log_info "Extracting toolchain"
    tar -xzf "${temp_dir}/${TOOLCHAIN_ARCHIVE}" -C "${SCRIPT_DIR}" || die "Toolchain extraction failed"
    
    log_success "Toolchain extracted"
}

setup_toolchain() {
    if [[ -f "${TOOLCHAIN_MARKER}" ]] && \
       [[ -d "${SCRIPT_DIR}/kernel/prebuilts" ]] && \
       [[ -d "${SCRIPT_DIR}/prebuilts" ]]; then
        log_info "Toolchain already installed"
        return 0
    fi
    
    log_info "Installing toolchain"
    
    download_toolchain
    
    if [[ ! -d "${SCRIPT_DIR}/kernel/prebuilts" ]] || [[ ! -d "${SCRIPT_DIR}/prebuilts" ]]; then
        die "Toolchain directories missing after extraction"
    fi
    
    touch "${TOOLCHAIN_MARKER}" 2>/dev/null || true
    log_success "Toolchain installed"
}

init_submodules() {
    log_info "Initializing submodules"
    
    if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
        log_warn "Not a git repository, skipping submodules"
        return 0
    fi

    if [[ ! -s "${SCRIPT_DIR}/.gitmodules" ]]; then
        log_info "No submodules configured"
        return 0
    fi
    
    git submodule init 2>/dev/null || log_warn "Submodule init failed"
    git submodule update 2>/dev/null || log_warn "Submodule update failed"
    
    log_success "Submodules initialized"
}

setup_environment() {
    export BUILD_KERNEL_VERSION="${BUILD_KERNEL_VERSION:-dev}"
    log_info "Kernel version: ${BUILD_KERNEL_VERSION}"
    
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        log_info "Running in GitHub Actions - limiting parallelism"
        export MAKEOPTS="-j2"
    fi
    
    mkdir -p "${SCRIPT_DIR}/custom_defconfigs"
    
    cat > "${SCRIPT_DIR}/custom_defconfigs/version_defconfig" << EOF
CONFIG_LOCALVERSION_AUTO=n
CONFIG_LOCALVERSION="-nolanarchie-${BUILD_KERNEL_VERSION}"
EOF

    cat > "${SCRIPT_DIR}/custom_defconfigs/disable_knox.config" << EOF
CONFIG_KNOX_KAP=n
CONFIG_KNOX_KAP_NGKSM=n
CONFIG_NGKPAD=n
CONFIG_RKP=n
CONFIG_RKP_KDP=n
CONFIG_UH=n
CONFIG_UH_RKP=n
CONFIG_TIMA=n
CONFIG_TIMA_RKP=n
CONFIG_SAMSUNG_SECURITY=n
CONFIG_PROCA=n
CONFIG_FIVE=n
CONFIG_FIVE_PA_FEATURE=n
CONFIG_SAMSUNG_PRODUCT_SHIP=y
CONFIG_LTO_NONE=y
CONFIG_LTO_CLANG=n
CONFIG_THINLTO=n
EOF

    export ARCH=arm64
    export PLATFORM_VERSION=13
    export TARGET_BUILD_VARIANT=user
    export CROSS_COMPILE="aarch64-linux-gnu-"
    export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
    
    local abs_out_dir="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ"
    export OUT_DIR="${abs_out_dir}"
    export DIST_DIR="${abs_out_dir}"
    export BUILD_CONFIG="${abs_out_dir}/build.config"
    export MERGE_CONFIG="${SCRIPT_DIR}/kernel-5.10/scripts/kconfig/merge_config.sh"

    export GKI_KERNEL_BUILD_OPTIONS="SKIP_MRPROPER=1 KMI_SYMBOL_LIST_STRICT_MODE=0 ABI_DEFINITION= BUILD_BOOT_IMG=1 MKBOOTIMG_PATH=${SCRIPT_DIR}/mkbootimg/mkbootimg.py KERNEL_BINARY=Image.gz BOOT_IMAGE_HEADER_VERSION=4 SKIP_VENDOR_BOOT=1 AVB_SIGN_BOOT_IMG=1 AVB_BOOT_PARTITION_SIZE=67108864 AVB_BOOT_KEY=${SCRIPT_DIR}/mkbootimg/tests/data/testkey_rsa2048.pem AVB_BOOT_ALGORITHM=SHA256_RSA2048 AVB_BOOT_PARTITION_NAME=boot GKI_RAMDISK_PREBUILT_BINARY=${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4 LTO=none"
    
    export MKBOOTIMG_EXTRA_ARGS="--os_version 12.0.0 --os_patch_level 2025-05-00 --pagesize 4096"
    
    export GKI_RAMDISK_PREBUILT_BINARY="${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4"
    
    export MAKE_MENUCONFIG="${MAKE_MENUCONFIG:-0}"
    if [[ "${MAKE_MENUCONFIG}" == "1" ]]; then
        export HERMETIC_TOOLCHAIN=0
        log_info "Menuconfig enabled"
    fi
    
    export WDIR="${SCRIPT_DIR}"
    
    log_success "Environment configured"
}

verify_prerequisites() {
    local missing=()
    
    [[ ! -d "${SCRIPT_DIR}/kernel-5.10" ]] && missing+=("kernel-5.10")
    [[ ! -d "${SCRIPT_DIR}/kernel" ]] && missing+=("kernel")
    [[ ! -d "${SCRIPT_DIR}/mkbootimg" ]] && missing+=("mkbootimg")
    [[ ! -f "${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4" ]] && missing+=("oem_prebuilt_images/gki-ramdisk.lz4")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required files:"
        printf '  - %s\n' "${missing[@]}"
        die "Required files missing"
    fi
    
    log_success "Prerequisites verified"
}

generate_build_config() {
    log_info "Generating build config"
    
    local abs_out_dir="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ"
    mkdir -p "${abs_out_dir}"
    
    local config_dir="${abs_out_dir}"
    rm -f "${config_dir}/build.config" \
          "${config_dir}/build.config.gki.aarch64" \
          "${config_dir}/build.config.mtk" 2>/dev/null || true
    
    cd "${SCRIPT_DIR}/kernel-5.10" || die "Cannot access kernel-5.10"
    
    python3 scripts/gen_build_config.py \
        --kernel-defconfig a16_00_defconfig \
        --kernel-defconfig-overlays entry_level.config \
        -m user \
        -o "${abs_out_dir}/build.config" || die "Build config generation failed"
    
    if [[ ! -f "${abs_out_dir}/build.config" ]]; then
        die "build.config was not created at ${abs_out_dir}/build.config"
    fi
    
    log_info "Build config created at: ${abs_out_dir}/build.config"
    
    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"
    
    local symlink_dirs=(
        "custom_defconfigs"
        "prebuilts_helio_g99"
        "oem_prebuilt_images"
    )
    
    for dir_name in "${symlink_dirs[@]}"; do
        if [[ -d "${SCRIPT_DIR}/${dir_name}" ]] && [[ ! -e "/${dir_name}" ]]; then
            log_info "Attempting symlink: /${dir_name}"
            if sudo ln -sf "${SCRIPT_DIR}/${dir_name}" "/${dir_name}" 2>/dev/null; then
                log_success "Symlink created: /${dir_name}"
            else
                log_warn "Symlink failed for /${dir_name}, continuing without it"
            fi
        elif [[ -e "/${dir_name}" ]]; then
            log_info "Symlink exists: /${dir_name}"
        fi
    done
    
    log_success "Build config generated"
}

build_kernel() {
    log_info "Building kernel"
    
    cd "${SCRIPT_DIR}/kernel" || die "Cannot access kernel directory"
    
    local build_result=0
    env ${GKI_KERNEL_BUILD_OPTIONS} ./build/build.sh || build_result=$?
    
    if [[ ${build_result} -ne 0 ]]; then
        log_warn "Build script returned error ${build_result}, checking outputs"
        
        local boot_img="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/boot.img"
        local kernel_img_gz="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
        
        if [[ -f "${boot_img}" ]] || [[ -f "${kernel_img_gz}" ]]; then
            log_success "Build artifacts found, continuing"
        else
            die "Build failed, no artifacts found"
        fi
    fi
    
    mkdir -p "${SCRIPT_DIR}/dist"
    
    local boot_img="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/boot.img"
    local kernel_img_gz="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
    
    if [[ -f "${boot_img}" ]]; then
        cp "${boot_img}" "${SCRIPT_DIR}/dist/" && log_success "Copied boot.img"
    else
        log_warn "boot.img not found"
    fi
    
    if [[ -f "${kernel_img_gz}" ]]; then
        cp "${kernel_img_gz}" "${SCRIPT_DIR}/dist/" && log_success "Copied Image.gz"
    else
        log_warn "Image.gz not found"
    fi
    
    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"
    log_success "Kernel build complete"
}

package_artifacts() {
    log_info "Packaging artifacts"
    
    cd "${SCRIPT_DIR}/dist" || die "Cannot access dist directory"
    
    local package_name="SukiSU-Ultra-SUSFS-SM-A165F-${BUILD_KERNEL_VERSION}"
    
    if [[ ! -f "boot.img" ]]; then
        die "boot.img not found in dist directory"
    fi
    
    log_info "Creating package with boot.img"
    
    tar -cvf "${package_name}.tar" boot.img || die "Tar creation failed"
    
    zip -9 "${package_name}-packaged.zip" "${package_name}.tar" || die "Zip creation failed"
    
    rm -f "${package_name}.tar" boot.img
    
    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"
    
    log_success "Package created: ${SCRIPT_DIR}/dist/${package_name}-packaged.zip"
}

main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "====================================================================="
    log_info "SukiSU-Ultra Build Script"
    log_info "====================================================================="
    
    mkdir -p "${SCRIPT_DIR}/dist"
    check_and_install_requirements
    init_submodules
    setup_toolchain
    verify_prerequisites
    generate_build_config
    setup_environment
    build_kernel
    package_artifacts
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "====================================================================="
    log_success "Build completed in ${duration} seconds"
    log_info "====================================================================="
    log_info "Output: ${SCRIPT_DIR}/dist/SukiSU-Ultra-SUSFS-SM-A165F-${BUILD_KERNEL_VERSION}-packaged.zip"
}

trap 'log_error "Build failed at line $LINENO"' ERR

main "$@"
