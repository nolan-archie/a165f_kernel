#!/bin/bash

#===============================================================================
# KernelSU Build Script for Samsung Galaxy A16 4G
# Architecture: arm64 | Platform: Android 12 | Kernel: 5.10
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

#===============================================================================
# Global Configuration
#===============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REQUIREMENTS_FILE="${SCRIPT_DIR}/.requirements"
readonly TOOLCHAIN_MARKER="${SCRIPT_DIR}/.toolchain_installed"
readonly TOOLCHAIN_URL="https://github.com/ravindu644/android_kernel_a165f/releases/download/toolchain/toolchain.tar.gz"
readonly TOOLCHAIN_ARCHIVE="toolchain.tar.gz"

# Color codes for better output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#===============================================================================
# Utility Functions
#===============================================================================

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

#===============================================================================
# Dependency Management
#===============================================================================

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
        die "Unsupported package manager. Please install dependencies manually."
    fi
}

install_dependencies() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    log_info "Detected package manager: ${pkg_manager}"
    
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
            
            log_info "Installing Arch Linux dependencies..."
            if ! sudo pacman -S --needed --noconfirm "${arch_packages[@]}"; then
                die "Failed to install dependencies"
            fi
            ;;
            
        apt)
            local debian_packages=(
                "build-essential"
                "rsync"
                "python2"
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
                "libssl-dev"
                "device-tree-compiler"
            )
            
            log_info "Installing Debian/Ubuntu dependencies..."
            sudo apt update || die "Failed to update package lists"
            if ! sudo apt install -y "${debian_packages[@]}"; then
                die "Failed to install dependencies"
            fi
            ;;
            
        dnf)
            log_info "Installing Fedora dependencies..."
            if ! sudo dnf install -y gcc gcc-c++ make rsync python2 git tar gzip curl wget bc cpio flex bison zip unzip openssl-devel dtc; then
                die "Failed to install dependencies"
            fi
            ;;
            
        *)
            die "Unsupported package manager: ${pkg_manager}"
            ;;
    esac
    
    log_success "Dependencies installed successfully"
}

check_and_install_requirements() {
    if [[ -f "${REQUIREMENTS_FILE}" ]]; then
        log_info "Requirements already satisfied (found ${REQUIREMENTS_FILE})"
        return 0
    fi
    
    log_info "First-time setup: Installing build requirements..."
    install_dependencies
    
    # Create marker file
    touch "${REQUIREMENTS_FILE}" || log_warn "Could not create requirements marker file"
    log_success "Requirements installation complete"
}

#===============================================================================
# Toolchain Management
#===============================================================================

download_toolchain() {
    local temp_dir
    temp_dir=$(mktemp -d) || die "Failed to create temporary directory"
    
    trap "rm -rf '${temp_dir}'" EXIT
    
    log_info "Downloading toolchain from ${TOOLCHAIN_URL}..."
    
    if ! curl -L --progress-bar -o "${temp_dir}/${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}"; then
        die "Failed to download toolchain"
    fi
    
    log_info "Extracting toolchain..."
    if ! tar -xzf "${temp_dir}/${TOOLCHAIN_ARCHIVE}" -C "${SCRIPT_DIR}"; then
        die "Failed to extract toolchain"
    fi
    
    log_success "Toolchain extracted successfully"
}

setup_toolchain() {
    # Check if toolchain is already installed
    if [[ -f "${TOOLCHAIN_MARKER}" ]] && \
       [[ -d "${SCRIPT_DIR}/kernel/prebuilts" ]] && \
       [[ -d "${SCRIPT_DIR}/prebuilts" ]]; then
        log_info "Toolchain already installed (found ${TOOLCHAIN_MARKER})"
        return 0
    fi
    
    log_info "Setting up Samsung NDK toolchain..."
    
    # Download and extract toolchain
    download_toolchain
    
    # Verify extraction
    if [[ ! -d "${SCRIPT_DIR}/kernel/prebuilts" ]] || [[ ! -d "${SCRIPT_DIR}/prebuilts" ]]; then
        die "Toolchain directories not found after extraction. Please check the archive contents."
    fi
    
    # Create marker file
    touch "${TOOLCHAIN_MARKER}" || log_warn "Could not create toolchain marker file"
    log_success "Toolchain setup complete"
}

#===============================================================================
# Git Submodule Management
#===============================================================================

init_submodules() {
    log_info "Initializing git submodules..."
    
    if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
        log_warn "Not a git repository. Skipping submodule initialization."
        return 0
    fi
    
    if ! git submodule init; then
        log_warn "Failed to initialize submodules (non-fatal)"
    fi
    
    if ! git submodule update; then
        log_warn "Failed to update submodules (non-fatal)"
    fi
    
    log_success "Submodule initialization complete"
}

#===============================================================================
# Build Configuration
#===============================================================================

setup_environment() {
    # Kernel version
    export BUILD_KERNEL_VERSION="${BUILD_KERNEL_VERSION:-dev}"
    log_info "Building kernel version: ${BUILD_KERNEL_VERSION}"
    
    # Create custom defconfigs directory
    mkdir -p "${SCRIPT_DIR}/custom_defconfigs"
    
    # Generate version defconfig
    cat > "${SCRIPT_DIR}/custom_defconfigs/version_defconfig" << EOF
CONFIG_LOCALVERSION_AUTO=n
CONFIG_LOCALVERSION="-nolanarchie-${BUILD_KERNEL_VERSION}"
EOF
    # OEM's variables from build_kernel.sh/README_Kernel.txt
export ARCH=arm64
export PLATFORM_VERSION=13
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
export OUT_DIR="../out/target/product/a16/obj/KERNEL_OBJ"
export DIST_DIR="../out/target/product/a16/obj/KERNEL_OBJ"
export BUILD_CONFIG="../out/target/product/a16/obj/KERNEL_OBJ/build.config"
export MERGE_CONFIG="${SCRIPT_DIR}/kernel-5.10/scripts/kconfig/merge_config.sh"

    # Build options
    export GKI_KERNEL_BUILD_OPTIONS="
    SKIP_MRPROPER=1 \
    KMI_SYMBOL_LIST_STRICT_MODE=0 \
    ABI_DEFINITION= \
    BUILD_BOOT_IMG=1 \
    MKBOOTIMG_PATH=${SCRIPT_DIR}/mkbootimg/mkbootimg.py \
    KERNEL_BINARY=Image.gz \
    BOOT_IMAGE_HEADER_VERSION=4 \
    SKIP_VENDOR_BOOT=1 \
    AVB_SIGN_BOOT_IMG=1 \
    AVB_BOOT_PARTITION_SIZE=67108864 \
    AVB_BOOT_KEY=${SCRIPT_DIR}/mkbootimg/tests/data/testkey_rsa2048.pem \
    AVB_BOOT_ALGORITHM=SHA256_RSA2048 \
    AVB_BOOT_PARTITION_NAME=boot \
    GKI_RAMDISK_PREBUILT_BINARY=${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4 \
    LTO=full \
"
    
    # Extra mkbootimg arguments
    export MKBOOTIMG_EXTRA_ARGS="
    --os_version 12.0.0 \
    --os_patch_level 2025-05-00 \
    --pagesize 4096 \
"
    
    export GKI_RAMDISK_PREBUILT_BINARY="${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4"
    
    # Menuconfig option
    export MAKE_MENUCONFIG="${MAKE_MENUCONFIG:-0}"
    if [[ "${MAKE_MENUCONFIG}" == "1" ]]; then
        export HERMETIC_TOOLCHAIN=0
        log_info "Menuconfig enabled"
    fi
    
    # Set WDIR for compatibility with DIST_CMDS in build.sh
    export WDIR="${SCRIPT_DIR}"
    
    log_success "Environment configured"
}

verify_prerequisites() {
    local missing_dirs=()
    
    # Check for required directories
    [[ ! -d "${SCRIPT_DIR}/kernel-5.10" ]] && missing_dirs+=("kernel-5.10")
    [[ ! -d "${SCRIPT_DIR}/kernel" ]] && missing_dirs+=("kernel")
    [[ ! -d "${SCRIPT_DIR}/mkbootimg" ]] && missing_dirs+=("mkbootimg")
    [[ ! -f "${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4" ]] && missing_dirs+=("oem_prebuilt_images/gki-ramdisk.lz4")
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Missing required directories/files:"
        printf '  - %s\n' "${missing_dirs[@]}"
        die "Please ensure all required files are present"
    fi
    
    log_success "Prerequisites verified"
}

#===============================================================================
# Build Functions
#===============================================================================

generate_build_config() {
    log_info "Generating build configuration..."
    
    # Ensure output directory exists
    mkdir -p "${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ"
    
    # Clean up old build.config files to avoid corruption from previous runs
    local config_dir="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ"
    rm -f "${config_dir}/build.config" \
          "${config_dir}/build.config.gki.aarch64" \
          "${config_dir}/build.config.mtk" 2>/dev/null || true
    
    cd "${SCRIPT_DIR}/kernel-5.10" || die "Failed to change directory to kernel-5.10"
    
    # Generate build.config with absolute path
    if ! python2 scripts/gen_build_config.py \
        --kernel-defconfig a16_00_defconfig \
        --kernel-defconfig-overlays entry_level.config \
        -m user \
        -o "${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/build.config"; then
        die "Failed to generate build configuration"
    fi
    
    cd "${SCRIPT_DIR}" || die "Failed to return to script directory"
    
    # Create symlinks for directories that scripts might need at root level
    local symlink_dirs=(
        "custom_defconfigs"
        "prebuilts_helio_g99"
        "oem_prebuilt_images"
    )
    
    for dir_name in "${symlink_dirs[@]}"; do
        if [[ -d "${SCRIPT_DIR}/${dir_name}" ]] && [[ ! -e "/${dir_name}" ]]; then
            log_info "Creating symlink for ${dir_name}..."
            if sudo ln -sf "${SCRIPT_DIR}/${dir_name}" "/${dir_name}"; then
                log_success "Symlink created: /${dir_name} -> ${SCRIPT_DIR}/${dir_name}"
            else
                log_warn "Failed to create symlink at /${dir_name}"
            fi
        elif [[ -e "/${dir_name}" ]]; then
            log_info "Symlink /${dir_name} already exists"
        fi
    done
    
    log_success "Build configuration generated"
}

build_kernel() {
    log_info "Building kernel..."
    
    cd "${SCRIPT_DIR}/kernel" || die "Failed to change directory to kernel"
    
    # Execute build - let it run naturally
    local build_result=0
    env ${GKI_KERNEL_BUILD_OPTIONS} ./build/build.sh || build_result=$?
    
    # If build failed, check if we can recover
    if [[ ${build_result} -ne 0 ]]; then
        log_warn "Build command returned error code ${build_result}, checking outputs..."
        
        # Check if the actual compilation succeeded even though the script failed
        local boot_img="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/boot.img"
        local kernel_img_gz="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
        
        if [[ -f "${boot_img}" ]] || [[ -f "${kernel_img_gz}" ]]; then
            log_success "Build artifacts found despite error - continuing..."
        else
            die "Kernel build failed - no usable artifacts found"
        fi
    fi
    
    # Copy artifacts to dist
    mkdir -p "${SCRIPT_DIR}/dist"
    
    local boot_img="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/boot.img"
    local kernel_img_gz="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
    
    if [[ -f "${boot_img}" ]]; then
        cp "${boot_img}" "${SCRIPT_DIR}/dist/" && log_success "Copied boot.img"
    else
        log_warn "boot.img not found at ${boot_img}"
    fi
    
    if [[ -f "${kernel_img_gz}" ]]; then
        cp "${kernel_img_gz}" "${SCRIPT_DIR}/dist/" && log_success "Copied Image.gz"
    else
        log_warn "Image.gz not found at ${kernel_img_gz}"
    fi
    
    cd "${SCRIPT_DIR}" || die "Failed to return to script directory"
    log_success "Kernel build completed"
}

build_vendor_boot() {
    log_info "Building vendor boot..."
    
    local vendor_boot_script="${SCRIPT_DIR}/prebuilts_helio_g99/scripts/build_vendor_boot.sh"
    
    if [[ ! -f "${vendor_boot_script}" ]]; then
        log_warn "Vendor boot script not found. Skipping vendor boot build."
        return 0
    fi
    
    # Run in a new bash session to avoid readonly variable conflict
    # The vendor script expects SCRIPT_DIR but we declare it readonly in main script
    if ! bash -c "export SCRIPT_DIR='${SCRIPT_DIR}'; source '${vendor_boot_script}'"; then
        log_warn "Vendor boot build failed (non-fatal)"
        return 0
    fi
    
    log_success "Vendor boot built successfully"
}

build_vendor_dlkm() {
    log_info "Building vendor DLKM..."
    
    local vendor_dlkm_script="${SCRIPT_DIR}/prebuilts_helio_g99/scripts/build_vendor_dlkm.sh"
    
    if [[ ! -f "${vendor_dlkm_script}" ]]; then
        log_warn "Vendor DLKM script not found. Skipping vendor DLKM build."
        return 0
    fi
    
    # Run in a new bash session to avoid readonly variable conflict
    # The vendor script expects SCRIPT_DIR but we declare it readonly in main script
    if ! bash -c "export SCRIPT_DIR='${SCRIPT_DIR}'; source '${vendor_dlkm_script}'"; then
        log_warn "Vendor DLKM build failed (non-fatal)"
        return 0
    fi
    
    log_success "Vendor DLKM built successfully"
}

package_artifacts() {
    log_info "Packaging build artifacts..."
    
    cd "${SCRIPT_DIR}/dist" || die "Failed to change directory to dist"
    
    local package_name="KernelSU-Next-SM-A165F-${BUILD_KERNEL_VERSION}"
    local required_files=()
    local optional_files=("vendor_boot.img" "vendor_dlkm.img")
    
    if [[ -f "boot.img" ]]; then
        required_files+=("boot.img")
    elif [[ -f "Image.gz" ]]; then
        log_warn "boot.img not found, using Image.gz instead"
        required_files+=("Image.gz")
    elif [[ -f "Image" ]]; then
        log_warn "boot.img not found, using Image instead"
        required_files+=("Image")
    else
        die "No kernel image files found"
    fi
    
    local files_to_tar=("${required_files[@]}")
    for file in "${optional_files[@]}"; do
        if [[ -f "${file}" ]]; then
            files_to_tar+=("${file}")
            log_info "Including ${file}"
        fi
    done

    #  UNCOMPRESSED TAR
    if ! tar -cvf "${package_name}.tar" "${files_to_tar[@]}"; then
        die "Failed to create tar archive"
    fi

    # Cleanup only source artifacts
    for file in "${files_to_tar[@]}"; do
        [[ -f "${file}" ]] && rm -f "${file}"
    done
    
    cd "${SCRIPT_DIR}" || die "Failed to return to script directory"
    
    log_success "Packaging complete: ${SCRIPT_DIR}/dist/${package_name}.tar"
}


#===============================================================================
# Main Build Flow
#===============================================================================

main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "====================================================================="
    log_info "KernelSU Build Script Started"
    log_info "====================================================================="
    
    # Setup phase
    mkdir -p "${SCRIPT_DIR}/dist"
    check_and_install_requirements
    init_submodules
    setup_toolchain
    verify_prerequisites
    
    # Generate build config BEFORE setting up environment
    # This must happen early, from kernel-5.10 directory
    generate_build_config
    
    # Now set up environment variables
    setup_environment
    
    # Build phase
    build_kernel
    package_artifacts
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
log_info "====================================================================="
log_success "Build completed successfully in ${duration} seconds"
log_info "====================================================================="
log_info "Output: ${SCRIPT_DIR}/dist/SukiSu-Ultra-SM-A165F-${BUILD_KERNEL_VERSION}.tar"

}

# Trap errors
trap 'log_error "Build failed at line $LINENO"' ERR

# Run main function
main "$@"
