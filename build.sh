#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_NAME="${PRODUCT_NAME:-a16}"
BUILD_VARIANT="${BUILD_VARIANT:-user}"
BUILD_KERNEL_VERSION="${BUILD_KERNEL_VERSION:-dev}"

REQUIREMENTS_FILE="${SCRIPT_DIR}/.requirements"
TOOLCHAIN_MARKER="${SCRIPT_DIR}/.toolchain_installed"
TOOLCHAIN_URL="https://github.com/ravindu644/android_kernel_a165f/releases/download/toolchain/toolchain.tar.gz"
TOOLCHAIN_ARCHIVE="toolchain.tar.gz"

KERNEL_ROOT="${SCRIPT_DIR}/kernel"
KERNEL_SRC_DIR="${SCRIPT_DIR}/kernel-5.10"
DIST_DIR="${SCRIPT_DIR}/dist"
OUT_DIR_ABS="${SCRIPT_DIR}/out/target/product/${PRODUCT_NAME}/obj/KERNEL_OBJ"

KERNEL_IMAGE_SRC="${OUT_DIR_ABS}/kernel-5.10/arch/arm64/boot/Image.gz"
KERNEL_IMAGE_STAGE="${OUT_DIR_ABS}/Image.gz"
BOOT_IMAGE_STAGE="${OUT_DIR_ABS}/boot.img"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() { log_error "$*"; exit 1; }

check_command() { command -v "$1" >/dev/null 2>&1; }

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
            sudo pacman -S --needed --noconfirm \
                base-devel rsync python git tar gzip curl wget bc cpio flex bison zip unzip openssl dtc \
                || die "Dependency install failed"
            ;;
        apt)
            sudo apt update || die "Package update failed"
            sudo apt install -y \
                build-essential rsync python3 python3-dev git tar gzip curl wget bc cpio flex bison zip unzip \
                libncurses-dev libssl-dev device-tree-compiler \
                || die "Dependency install failed"
            ;;
        dnf)
            sudo dnf install -y \
                gcc gcc-c++ make rsync python3 git tar gzip curl wget bc cpio flex bison zip unzip openssl-devel dtc \
                || die "Dependency install failed"
            ;;
        zypper)
            sudo zypper --non-interactive install \
                gcc gcc-c++ make rsync python3 git tar gzip curl wget bc cpio flex bison zip unzip libopenssl-devel dtc \
                || die "Dependency install failed"
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

    install_dependencies
    touch "${REQUIREMENTS_FILE}" 2>/dev/null || true
    log_success "Requirements satisfied"
}

download_toolchain() {
    local temp_dir
    temp_dir=$(mktemp -d) || die "Cannot create temp directory"
    trap 'rm -rf "${temp_dir}"' EXIT

    log_info "Downloading toolchain"
    curl -L --progress-bar -o "${temp_dir}/${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}" \
        || die "Toolchain download failed"

    log_info "Extracting toolchain"
    tar -xzf "${temp_dir}/${TOOLCHAIN_ARCHIVE}" -C "${SCRIPT_DIR}" \
        || die "Toolchain extraction failed"

    log_success "Toolchain extracted"
}

setup_toolchain() {
    if [[ -f "${TOOLCHAIN_MARKER}" ]] && [[ -d "${SCRIPT_DIR}/kernel/prebuilts" ]] && [[ -d "${SCRIPT_DIR}/prebuilts" ]]; then
        log_info "Toolchain already installed"
        return 0
    fi

    download_toolchain

    if [[ ! -d "${SCRIPT_DIR}/kernel/prebuilts" || ! -d "${SCRIPT_DIR}/prebuilts" ]]; then
        die "Toolchain directories missing after extraction"
    fi

    touch "${TOOLCHAIN_MARKER}" 2>/dev/null || true
    log_success "Toolchain installed"
}

fix_gen_build_config() {
    local py="${SCRIPT_DIR}/kernel-5.10/scripts/gen_build_config.py"

    if [[ ! -f "${py}" ]]; then
        log_warn "gen_build_config.py not found, skipping fix"
        return 0
    fi

    if grep -q '^print(' "${py}" 2>/dev/null && ! grep -q '^print ' "${py}" 2>/dev/null; then
        log_info "gen_build_config.py already fixed, skipping"
        return 0
    fi

    log_info "Fixing gen_build_config.py for Python 3"
    python3 - "${py}" <<'PYEOF'
import sys

py = sys.argv[1]
with open(py, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    stripped = line.lstrip()
    if stripped.startswith('print ') and not stripped.startswith('print('):
        new_line = line.replace('print ', 'print(', 1)
        if new_line.endswith('\n'):
            new_line = new_line[:-1] + ')\n'
        else:
            new_line = new_line + ')'
        new_lines.append(new_line)
    else:
        new_lines.append(line)

with open(py, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
PYEOF

    if python3 -m py_compile "${py}"; then
        log_success "gen_build_config.py syntax OK"
    else
        log_warn "Syntax check failed"
    fi
}

generate_build_config() {
    log_info "Generating build config"

    mkdir -p "${SCRIPT_DIR}/kernel-5.10/arch/arm64/configs"
    cd "${SCRIPT_DIR}/kernel-5.10/arch/arm64/configs" || die "Cannot access configs"

    {
        cat a16_00_defconfig
        [[ -f entry_level.config ]] && cat entry_level.config
        cat "${SCRIPT_DIR}/custom_defconfigs/custom_defconfig"
        printf 'CONFIG_LOCALVERSION_AUTO=n\nCONFIG_LOCALVERSION="-nolanarchie-dev"\n'
    } > a16_00_custom_defconfig

    log_info "Merged defconfig lines: $(wc -l < a16_00_custom_defconfig)"

    mkdir -p "${OUT_DIR_ABS}"
    rm -f "${OUT_DIR_ABS}/build.config" \
          "${OUT_DIR_ABS}/build.config.gki.aarch64" \
          "${OUT_DIR_ABS}/build.config.mtk"

    cd "${SCRIPT_DIR}/kernel-5.10" || die "Cannot access kernel-5.10"

    python3 scripts/gen_build_config.py \
        --kernel-defconfig a16_00_custom_defconfig \
        -m "${BUILD_VARIANT}" \
        -o "${OUT_DIR_ABS}/build.config" \
        || die "Build config generation failed"

    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"
    log_success "Build config generated"
}

create_symlinks() {
    log_info "Creating root symlinks"
    for d in custom_defconfigs prebuilts_helio_g99 oem_prebuilt_images; do
        if [[ -d "${SCRIPT_DIR}/${d}" ]] && [[ ! -e "/${d}" ]]; then
            if sudo ln -sf "${SCRIPT_DIR}/${d}" "/${d}" 2>/dev/null; then
                log_success "Symlink created: /${d}"
            else
                log_warn "Symlink failed for /${d}, continuing"
            fi
        elif [[ -e "/${d}" ]]; then
            log_info "Symlink exists: /${d}"
        fi
    done
}

prepare_boot_staging() {
    log_info "Preparing boot image staging"

    mkdir -p "${OUT_DIR_ABS}" "${DIST_DIR}"

    rm -f "${OUT_DIR_ABS}/boot.img" \
          "${DIST_DIR}/boot.img" \
          "${DIST_DIR}/Image.gz" \
          "${DIST_DIR}/manifest.txt" \
          "${DIST_DIR}/checksums.sha256"

    log_info "Not pre-touching ${OUT_DIR_ABS}/Image.gz; build.sh writes it there directly after compiling ${KERNEL_IMAGE_SRC}"
}

setup_environment() {
    export ARCH=arm64
    export PLATFORM_VERSION=13
    export TARGET_BUILD_VARIANT="${BUILD_VARIANT}"
    export CROSS_COMPILE="aarch64-linux-gnu-"
    export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"

    export OUT_DIR="../out/target/product/${PRODUCT_NAME}/obj/KERNEL_OBJ"
    export DIST_DIR="../out/target/product/${PRODUCT_NAME}/obj/KERNEL_OBJ"
    export BUILD_CONFIG="../out/target/product/${PRODUCT_NAME}/obj/KERNEL_OBJ/build.config"

    export MERGE_CONFIG="${SCRIPT_DIR}/kernel-5.10/scripts/kconfig/merge_config.sh"

    export GKI_RAMDISK_PREBUILT_BINARY="${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4"
    export MKBOOTIMG_EXTRA_ARGS="--os_version 12.0.0 --os_patch_level 2025-05-00 --pagesize 4096"

    export SKIP_MRPROPER=1
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export ABI_DEFINITION=
    export BUILD_BOOT_IMG=1
    export MKBOOTIMG_PATH="${SCRIPT_DIR}/mkbootimg/mkbootimg.py"
    export KERNEL_BINARY=Image.gz
    export BOOT_IMAGE_HEADER_VERSION=4
    export SKIP_VENDOR_BOOT=1
    export AVB_SIGN_BOOT_IMG=1
    export AVB_BOOT_PARTITION_SIZE=67108864
    export AVB_BOOT_KEY="${SCRIPT_DIR}/mkbootimg/tests/data/testkey_rsa2048.pem"
    export AVB_BOOT_ALGORITHM=SHA256_RSA2048
    export AVB_BOOT_PARTITION_NAME=boot
    export LTO=thin
    export KCFLAGS="-Wframe-larger-than=16384"

    export WDIR="${SCRIPT_DIR}"

    log_success "Environment configured"
}

verify_prerequisites() {
    local missing=()
    [[ ! -d "${SCRIPT_DIR}/kernel-5.10" ]] && missing+=("kernel-5.10")
    [[ ! -d "${SCRIPT_DIR}/kernel" ]] && missing+=("kernel")
    [[ ! -d "${SCRIPT_DIR}/mkbootimg" ]] && missing+=("mkbootimg")
    [[ ! -f "${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4" ]] && missing+=("oem_prebuilt_images/gki-ramdisk.lz4")
    [[ ! -f "${SCRIPT_DIR}/custom_defconfigs/custom_defconfig" ]] && missing+=("custom_defconfigs/custom_defconfig")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required files:"
        printf '  - %s\n' "${missing[@]}"
        die "Required files missing"
    fi

    log_success "Prerequisites verified"
}

build_kernel() {
    log_info "Building kernel"
    cd "${KERNEL_ROOT}" || die "Cannot access kernel directory"

    ./build/build.sh 2>&1 | tee "${SCRIPT_DIR}/build.log"
    local build_result=${PIPESTATUS[0]}

    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"

    if [[ ${build_result} -ne 0 ]]; then
        log_warn "Build script returned error ${build_result}, checking outputs"
        if [[ -f "${BOOT_IMAGE_STAGE}" || -f "${KERNEL_IMAGE_SRC}" || -f "${KERNEL_IMAGE_STAGE}" ]]; then
            log_warn "Some build artifacts exist; continuing to validate them"
        else
            die "Build failed and no artifacts were produced"
        fi
    fi

    log_success "Kernel build complete"
}

sync_artifacts() {
    log_info "Syncing final artifacts"

    if [[ ! -f "${KERNEL_IMAGE_SRC}" ]]; then
        die "Expected kernel image missing: ${KERNEL_IMAGE_SRC}"
    fi

    if [[ -L "${KERNEL_IMAGE_STAGE}" ]]; then
        :
    elif [[ -f "${KERNEL_IMAGE_STAGE}" ]]; then
        if ! cmp -s "${KERNEL_IMAGE_SRC}" "${KERNEL_IMAGE_STAGE}"; then
            log_warn "Staged Image.gz differs from source; refreshing it"
            cp -f "${KERNEL_IMAGE_SRC}" "${KERNEL_IMAGE_STAGE}"
        fi
    else
        cp -f "${KERNEL_IMAGE_SRC}" "${KERNEL_IMAGE_STAGE}"
    fi

    if [[ ! -f "${BOOT_IMAGE_STAGE}" ]]; then
        die "boot.img not found in ${OUT_DIR_ABS}"
    fi

    cp -f "${BOOT_IMAGE_STAGE}" "${DIST_DIR}/boot.img"
    cp -f "${KERNEL_IMAGE_SRC}" "${DIST_DIR}/Image.gz"

    log_success "Copied boot.img and Image.gz to dist"
}

verify_boot_image_if_possible() {
    if check_command magiskboot; then
        local tmpdir
        tmpdir=$(mktemp -d)
        cp -f "${DIST_DIR}/boot.img" "${tmpdir}/boot.img"

        (
            cd "${tmpdir}"
            magiskboot unpack boot.img >/dev/null 2>&1
        ) || {
            rm -rf "${tmpdir}"
            die "magiskboot could not unpack boot.img"
        }

        if [[ -f "${tmpdir}/kernel" ]]; then
            if cmp -s "${tmpdir}/kernel" "${DIST_DIR}/Image.gz"; then
                log_success "boot.img kernel matches Image.gz"
            else
                rm -rf "${tmpdir}"
                die "boot.img kernel does not match the built Image.gz"
            fi
        else
            log_warn "magiskboot unpacked boot.img but kernel file was not found"
        fi

        rm -rf "${tmpdir}"
    else
        log_warn "magiskboot not found; skipping boot.img kernel verification"
    fi
}

write_manifest() {
    log_info "Writing manifest"

    {
        echo "build_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "product=${PRODUCT_NAME}"
        echo "variant=${BUILD_VARIANT}"
        echo "kernel_version=${BUILD_KERNEL_VERSION}"
        echo "kernel_image=${DIST_DIR}/Image.gz"
        echo "boot_image=${DIST_DIR}/boot.img"
        echo "kernel_sha256=$(sha256sum "${DIST_DIR}/Image.gz" | awk '{print $1}')"
        echo "boot_sha256=$(sha256sum "${DIST_DIR}/boot.img" | awk '{print $1}')"
    } > "${DIST_DIR}/manifest.txt"

    sha256sum "${DIST_DIR}/boot.img" "${DIST_DIR}/Image.gz" > "${DIST_DIR}/checksums.sha256"
    log_success "Manifest written"
}

package_artifacts() {
    log_info "Packaging artifacts"
    cd "${DIST_DIR}" || die "Cannot access dist directory"

    if [[ ! -f "boot.img" ]]; then
        die "boot.img not found in dist directory"
    fi

    if [[ ! -f "Image.gz" ]]; then
        die "Image.gz not found in dist directory"
    fi

    local package_name="SukiSU-Ultra-A165F-${BUILD_KERNEL_VERSION}"
    log_info "Creating package"

    tar -cvf "${package_name}.tar" boot.img Image.gz manifest.txt checksums.sha256 >/dev/null \
        || die "Tar creation failed"

    zip -9 "${package_name}-packaged.zip" "${package_name}.tar" >/dev/null \
        || die "Zip creation failed"

    log_success "Package created: ${DIST_DIR}/${package_name}-packaged.zip"
}

main() {
    local start_time end_time duration
    start_time=$(date +%s)

    log_info "====================================================================="
    log_info "SukiSU-Ultra Build Script"
    log_info "====================================================================="

    mkdir -p "${DIST_DIR}"

    check_and_install_requirements
    setup_toolchain
    fix_gen_build_config
    verify_prerequisites
    generate_build_config
    create_symlinks
    setup_environment
    prepare_boot_staging
    build_kernel
    sync_artifacts
    verify_boot_image_if_possible
    write_manifest
    package_artifacts

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    log_info "====================================================================="
    log_success "Build completed in ${duration} seconds"
    log_info "====================================================================="
    log_info "Output: ${DIST_DIR}/SukiSU-Ultra-A165F-${BUILD_KERNEL_VERSION}-packaged.zip"
    log_info "Flashable boot image: ${DIST_DIR}/boot.img"
}

trap 'log_error "Build failed at line $LINENO"' ERR
main "$@"