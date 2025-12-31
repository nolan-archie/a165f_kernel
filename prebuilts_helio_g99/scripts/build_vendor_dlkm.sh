#!/bin/bash

# core variables
REPO_ROOT="${SCRIPT_DIR}"
LKM_TOOLS_DIR="${REPO_ROOT}/prebuilts_helio_g99/tools/LKM_Tools"
KBUILD_PATH="${REPO_ROOT}/out/target/product/a16/obj/KERNEL_OBJ"
AIT_DIR="${REPO_ROOT}/prebuilts_helio_g99/tools/AIT"
PKG_VENDOR_DLKM="${LKM_TOOLS_DIR}/03.prepare_vendor_dlkm.sh"

# input variables for LKM_Tools
STAGING_DIR="${KBUILD_PATH}"
SYSTEM_MAP="${KBUILD_PATH}/kernel-5.10/System.map"
STRIP_TOOL="${REPO_ROOT}/prebuilts/clang/host/linux-x86/clang-r416183b/bin/llvm-strip"
VENDOR_DLKM_MODULES_LIST="${REPO_ROOT}/prebuilts_helio_g99/vendor_dlkm/modules_list.txt"
VENDOR_BOOT_MODULES_LIST="${REPO_ROOT}/prebuilts_helio_g99/vendor_boot/modules_list.txt"
VENDOR_DLKM_MODULES_LOAD_FILE="${REPO_ROOT}/prebuilts_helio_g99/vendor_dlkm/modules.load"
OUTPUT_DIR="${AIT_DIR}/EXTRACTED_IMAGES/extracted_vendor_dlkm"
MODULES_OUTPUT_DIR="${OUTPUT_DIR}/lib/modules"

# Function to replace a key=value pair in a config file
replace_config_value() {
    local file="$1"
    local var_name="$2"
    local new_value="$3"

    if [ ! -f "$file" ]; then
        echo "Error: Config file not found: $file"
        return 1
    fi
    sed -i "s|^\($var_name=\).*|\1$new_value|" "$file" 
}

# 01. run LKM_Tools
# Documentation: ./03.prepare_vendor_dlkm.sh <modules_list> <staging_dir> <oem_load_file> <system_map> <strip_tool> <output_dir> <vendor_boot_list> <nh_dir> [blacklist_file]
package_modules() {
    mkdir -p "${MODULES_OUTPUT_DIR}" && \
        "${PKG_VENDOR_DLKM}" \
            "${VENDOR_DLKM_MODULES_LIST}" \
            "${STAGING_DIR}" \
            "${VENDOR_DLKM_MODULES_LOAD_FILE}" \
            "${SYSTEM_MAP}" \
            "${STRIP_TOOL}" \
            "${MODULES_OUTPUT_DIR}" \
            "${VENDOR_BOOT_MODULES_LIST}" \
            "" \
            ""
}

# 02. replace the config values
replace_config_values() {
    replace_config_value "${AIT_DIR}/CONFIGS/vendor_dlkm_repack.conf" "SOURCE_DIR" "${OUTPUT_DIR}" && \
    replace_config_value "${AIT_DIR}/CONFIGS/vendor_dlkm_repack.conf" "OUTPUT_IMAGE" "${REPO_ROOT}/dist/vendor_dlkm.img"
}

# 03. build vendor_dlkm.img
build_vendor_dlkm() {
    cd "${AIT_DIR}" && \
        sudo ./android_image_tools.sh --conf=${AIT_DIR}/CONFIGS/vendor_dlkm_repack.conf
}

# main execution
{ package_modules && \
    replace_config_values && \
    build_vendor_dlkm
} || {
    echo "Error: Failed to build the vendor_dlkm"
    exit 1
}
