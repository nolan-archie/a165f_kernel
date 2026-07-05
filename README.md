# Samsung Galaxy A16 Kernel

Custom kernel source and GitHub Actions build workflow for the Samsung Galaxy A16 LTE family, focused on the SM-A165F and compatible A15/A16 variants used by this tree.

This repository builds a Linux 5.10 Android kernel with SukiSU Ultra and SUSFS integration. The weekly workflow is the main supported build path: it checks out this source tree, downloads the toolchain, installs SukiSU Ultra, refreshes SUSFS from upstream, builds `boot.img`, and publishes release artifacts.

## Device Scope

Target devices declared in the AnyKernel package:

- `a16`
- `a165f`
- `a155f`
- `A165F`
- `A155F`

Primary target:

- Samsung Galaxy A16 LTE, SM-A165F
- MediaTek Helio G99 / MT6789 platform
- Android platform version used by the workflow: `13`
- Kernel tree: `kernel-5.10`

Do not flash this on an unsupported device or bootloader variant.

## Build Outputs

The weekly workflow publishes these artifacts when the build succeeds:

- `boot.img` - signed boot image
- `Image.gz` - compressed kernel image
- `SukiSU-Ultra-A165F-<version>.zip` - AnyKernel3 flashable package
- `SukiSU-Ultra-A165F-<version>.tar` - Odin-style archive containing `boot.img` and, when present, `Image.gz`
- `build.log` - uploaded separately as a workflow artifact for debugging

Release metadata includes the SukiSU branch, SUSFS branch, detected SUSFS version, manager version, and kernel version.

## Weekly Workflow

Workflow file:

- `.github/workflows/weekly-build.yml`

Triggers:

- Runs every Monday at `00:00 UTC`
- Can be started manually from GitHub Actions using `workflow_dispatch`

Manual inputs:

| Input | Default | Purpose |
| --- | --- | --- |
| `sukisu_branch` | `builtin` | Branch, tag, or commit passed to the SukiSU Ultra setup script. |
| `susfs_branch` | `gki-android13-5.10` | Branch, tag, or commit cloned from `simonpunk/susfs4ksu`. |
| `build_version` | empty | Optional release/version label. Empty uses an automatic commit-count version. |
| `manager_version` | empty | Optional manager version override. Empty resolves the latest SukiSU Ultra release when available. |

The workflow refreshes SUSFS on every run by cloning the selected `susfs_branch` and copying:

- `kernel_patches/fs/susfs.c`
- `kernel_patches/include/linux/susfs.h`
- `kernel_patches/include/linux/susfs_def.h`

It then reads `SUSFS_VERSION` from `kernel-5.10/include/linux/susfs.h`. The workflow does not pin the version number; it tracks the latest commit on the selected SUSFS branch.

## Kernel Features

Enabled or integrated by this tree and workflow:

- SukiSU Ultra kernel root support
- SUSFS kernel-side hiding and spoofing support
- SUSFS path, mount, kstat, uname, cmdline/bootconfig, open redirect, and map options
- SUSFS/KSU symbol hiding option
- AnyKernel3 packaging
- Odin tar packaging
- Samsung security-related config overrides for build flexibility
- Boot image signing with the test key included in the source tree

The workflow writes these generated config overlays during the build:

- `permissive.config`
- `susfs.config`

SUSFS options written by the workflow:

```text
CONFIG_KSU=y
CONFIG_KSU_MANUAL_SU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
```

## Repository Layout

```text
.
├── .github/workflows/weekly-build.yml   # Main CI build and release workflow
├── build.sh                             # Local build helper
├── custom_defconfigs/                   # Local defconfig overlays
├── kernel/                              # Samsung/Android build orchestration
├── kernel-5.10/                         # Main Linux 5.10 kernel source tree
├── mkbootimg/                           # Android boot image tools
├── oem_prebuilt_images/                 # Required OEM/prebuilt boot assets
├── prebuilts_helio_g99/                 # Platform-specific prebuilt tools
└── README_Kernel.txt                    # Original vendor kernel notes
```

## Local Build

The GitHub Actions workflow is the supported build path. Local builds may require root permissions for expected Samsung build-directory symlinks and a matching toolchain layout.

Basic local entry point:

```bash
./build.sh
```

Useful environment variables:

```bash
export BUILD_KERNEL_VERSION="custom-v1"
export MAKE_MENUCONFIG=1
./build.sh
```

Local build output is expected under `dist/` when successful.

## Flashing

Flashing a custom kernel requires an unlocked bootloader. Back up your data before flashing.

Fastboot or recovery:

```bash
fastboot flash boot boot.img
fastboot reboot
```

Custom recovery:

- Flash the generated AnyKernel3 ZIP, or
- Flash `boot.img` directly to the boot partition.

Odin:

- Use the generated `.tar` package in Odin's AP slot.
- Confirm the package is intended for your exact device variant before flashing.

## Notes

- The workflow currently uses `gki-android13-5.10` from SUSFS because this kernel is a 5.10 tree built with Android platform version 13.
- Changing `susfs_branch` to a branch for another Android or kernel version can break compilation.
- SukiSU Ultra's `builtin` branch currently includes SUSFS-aware code paths, so the workflow skips reapplying the SUSFS KernelSU patch when the SukiSU tree already contains the SUSFS Kconfig block.
- The kernel's base VFS/proc/SELinux SUSFS hooks are maintained in this repository. The workflow updates the SUSFS source/header files and KernelSU side each run, but it does not blindly merge the large upstream kernel patch into the vendor tree.

## Credits

This project depends on work from the Android, Linux, Samsung, KernelSU, SukiSU, SUSFS, and Android modding communities.

- Linux kernel: https://www.kernel.org/
- Android Open Source Project: https://android.googlesource.com/
- Samsung Open Source Release Center: https://opensource.samsung.com/
- SukiSU Ultra: https://github.com/SukiSU-Ultra/SukiSU-Ultra
- SUSFS for KernelSU: https://gitlab.com/simonpunk/susfs4ksu
- AnyKernel3: https://github.com/osm0sis/AnyKernel3
- Android boot image tools / mkbootimg: https://android.googlesource.com/platform/system/tools/mkbootimg/
- GitHub Actions: https://docs.github.com/actions
- ncipollo release action: https://github.com/ncipollo/release-action
- actions/checkout: https://github.com/actions/checkout
- actions/cache: https://github.com/actions/cache
- actions/upload-artifact: https://github.com/actions/upload-artifact

Additional credit goes to upstream kernel maintainers, Samsung's vendor kernel release, MediaTek platform contributors, and the developers maintaining the public rooting and recovery tooling used by this build.

## Disclaimer

This repository is for kernel development and personal device builds. You are responsible for anything you flash. A bad kernel or a mismatched boot image can bootloop or brick a device.
