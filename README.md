# SukiSU Ultra Kernel — Samsung Galaxy A16 (SM-A165F)

A professional-grade, custom Android 13 (Platform SDK 33) kernel for the Samsung Galaxy A16 (SM-A165F) powered by the MediaTek Helio G99 (MT6789) SoC. This repository provides a complete, automated build pipeline featuring **KernelSU** with **SUSFS** integration and stripped Samsung security features (KNOX, RKP, TIMA, DEFEX).

---

## Features

- **KernelSU (SukiSU Ultra)**: Fully-integrated kernel-level root solution.
- **SUSFS Support**: Spoofing and hiding capabilities integrated into the kernel virtual filesystem layer for seamless root detection evasion.
- **Disabled Knox & Security**: Anti-root mechanisms, including Samsung Knox, RKP (Real-time Kernel Protection), DEFEX, TIMA, and UH, are disabled at the configuration level to ensure maximum system flexibility.
- **MediaTek BT & WLAN Modules**: Built-in support for external MediaTek Bluetooth and wireless drivers.
- **Automated Packaging**: Compiles, signs, and packages the final kernel into an Odin-flashable `.tar` archive enclosed in a standard `.zip` file.

---

## Directory Structure

```text
├── build.sh                 # Main automated orchestration build script
├── README_Kernel.txt        # Original Samsung reference documentation
├── custom_defconfigs/       # Target configurations (custom_defconfig, droidspaces_defconfig)
├── kernel/                  # Build orchestration tools, environments, and static analysis
├── kernel-5.10/             # Primary Linux 5.10 GKI kernel source tree
├── KernelSU/                # KernelSU root implementation and core files
├── mkbootimg/               # Android command-line tools for working with boot images
├── oem_prebuilt_images/     # OEM binary dependencies (e.g., gki-ramdisk.lz4)
└── prebuilts_helio_g99/     # Platform-specific prebuilt compilers and tools
```

---

## Requirements & Dependencies

The main build script `build.sh` automatically detects your system's package manager and installs all necessary packages. The following distributions are supported:

- **Arch Linux**: `base-devel`, `rsync`, `git`, `tar`, `gzip`, `curl`, `wget`, `bc`, `cpio`, `flex`, `bison`, `zip`, `unzip`, `openssl`, `dtc`
- **Ubuntu/Debian**: `build-essential`, `rsync`, `python3`, `git`, `tar`, `gzip`, `curl`, `wget`, `bc`, `cpio`, `flex`, `bison`, `zip`, `unzip`, `libncurses-dev`, `libssl-dev`, `device-tree-compiler`
- **Fedora/RHEL**: `gcc`, `gcc-c++`, `make`, `rsync`, `python3`, `git`, `tar`, `gzip`, `curl`, `wget`, `bc`, `cpio`, `flex`, `bison`, `zip`, `unzip`, `openssl-devel`, `dtc`

---

## Build Pipeline

The `build.sh` orchestrator implements a 9-stage compilation pipeline:

1. **System Check**: Installs distribution-specific package requirements.
2. **Submodule Init**: Ensures dependent submodules (e.g., KernelSU) are checked out and up to date.
3. **Toolchain Extraction**: Downloads and extracts the pre-configured Clang/LLVM-based toolchain from AOSP/upstream repositories.
4. **Prerequisites Verification**: Validates the presence of crucial trees (`kernel-5.10`, `kernel`, `mkbootimg`, and prebuilt RAMDISK files).
5. **Configuration Generation**: Generates `build.config` based on the standard `a16_00_defconfig` and `entry_level.config` overlay.
6. **Environment Formulation**: Appends Knox disabling variables, custom build versioning, and GKI kernel options (such as skipping KMI checking and generating a signed boot partition).
7. **Symlink Creation**: Configures symbolic links for root directory structures (`/custom_defconfigs`, `/prebuilts_helio_g99`, `/oem_prebuilt_images`) which the internal Samsung build environment expects.
8. **Kernel Compilation**: Builds the kernel binaries and generates a GKI-compliant `boot.img`.
9. **Odin Packaging**: Moves artifacts to the `dist/` directory, packages `boot.img` as an Odin-flashable `.tar`, and wraps it in a `.zip` archive.

---

## Quick Start

### 1. Build the Kernel
To initiate the automated build process, run the root orchestration script:

```bash
./build.sh
```

### 2. Output Location
Upon a successful build, the output ZIP package will be created at:
```text
dist/SukiSU-Ultra-SUSFS-SM-A165F-<version>-packaged.zip
```
Inside this ZIP, you will find `SukiSU-Ultra-SUSFS-SM-A165F-<version>.tar` containing the compiled and signed `boot.img`.

---

## Advanced Options & Environment Variables

You can customize the compilation by defining variables before executing the build script:

### Custom Kernel Suffix/Version
To define a custom version string to identify your build:
```bash
export BUILD_KERNEL_VERSION="custom-v1.0"
./build.sh
```

### Enable Menuconfig
To make custom configurations directly in the Linux Kernel config menu before building:
```bash
export MAKE_MENUCONFIG=1
./build.sh
```

---

## Flashing Instructions

> [!WARNING]
> Flashing custom kernels requires an unlocked bootloader and carries the risk of bricking your device. Always back up your data before proceeding.

### Method 1: Odin (Recommended for Samsung Stock)
1. Unzip the packaged output to retrieve the `SukiSU-Ultra-SUSFS-SM-A165F-<version>.tar` archive.
2. Boot your SM-A165F into **Download Mode**.
3. Open **Odin** on your PC and place the `.tar` file in the **AP** slot.
4. Disable "Auto Reboot" in Odin options.
5. Click **Start** to flash. Once completed, reboot your device.

### Method 2: TWRP / Custom Recovery
1. Push the compiled `boot.img` (extracted from the `.tar` archive) to your phone's storage.
2. Boot into your custom recovery.
3. Select **Install** -> **Install Image**.
4. Choose `boot.img` and select the **Boot** partition.
5. Swipe to confirm flash, then reboot system.
