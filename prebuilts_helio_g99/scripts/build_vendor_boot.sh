#!/bin/bash

# core variables
REPO_ROOT="${SCRIPT_DIR}"
LKM_TOOLS_DIR="${REPO_ROOT}/prebuilts_helio_g99/tools/LKM_Tools"
KBUILD_PATH="${REPO_ROOT}/out/target/product/a16/obj/KERNEL_OBJ"
PKG_VENDOR_BOOT="${LKM_TOOLS_DIR}/02.prepare_vendor_boot_modules.sh"
BOOT_EDITOR_DIR="${REPO_ROOT}/prebuilts_helio_g99/tools/BOOT_EDITOR"

# input variables for LKM_Tools
STAGING_DIR="${KBUILD_PATH}"
SYSTEM_MAP="${KBUILD_PATH}/kernel-5.10/System.map"
STRIP_TOOL="${REPO_ROOT}/prebuilts/clang/host/linux-x86/clang-r416183b/bin/llvm-strip"
MODULES_LIST="${REPO_ROOT}/prebuilts_helio_g99/vendor_boot/modules_list.txt"
OEM_LOAD_FILE="${REPO_ROOT}/prebuilts_helio_g99/vendor_boot/modules.load"
OUTPUT_DIR="${BOOT_EDITOR_DIR}/build/unzip_boot/root.1/lib/modules"

# 01. run LKM_Tools
# Documentation: ./02.prepare_vendor_boot_modules.sh <modules_list> <staging_dir> <oem_load_file> <system_map> <strip_tool> <output_dir>
package_modules() {
    mkdir -p "${OUTPUT_DIR}" && \
        "${PKG_VENDOR_BOOT}" \
            "${MODULES_LIST}" \
            "${STAGING_DIR}" \
            "${OEM_LOAD_FILE}" \
            "${SYSTEM_MAP}" \
            "${STRIP_TOOL}" \
            "${OUTPUT_DIR}"
}

# 02. build the vendor boot
build_vendor_boot() {
    cd "${BOOT_EDITOR_DIR}" && \
        ./gradlew pack && \
        mv vendor_boot.img.signed "${REPO_ROOT}/dist/vendor_boot.img"
        cd "${REPO_ROOT}"
}

# main execution
{ package_modules && \
    build_vendor_boot
} || {
    echo "Error: Failed to build the vendor boot"
    exit 1
}
