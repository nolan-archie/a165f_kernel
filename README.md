# a165f_kernel

Custom Linux 5.10 kernel for the Samsung Galaxy A16 (SM-A165F), built on the
stock Samsung/MediaTek source with root support and filesystem-hiding
(SuSFS) integrated at the kernel level.

Two branches, two root implementations, one shared build pipeline:

| Branch       | Root manager                                      | Hook type          |
|--------------|----------------------------------------------------|---------------------|
| `main`       | [KernelSU-Next](https://github.com/pershoot/KernelSU-Next) (`dev-susfs` fork) | Kprobes / Manual |
| `susfs-dev`  | [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) (`builtin` fork) | Kprobes / LKM    |

Both branches ship [SUSFS4KSU](https://gitlab.com/simonpunk/susfs4ksu) —
kernel-side hiding of root artifacts from userspace detection (mount
namespaces, `/proc` entries, `open()` redirects, etc.) — wired directly into
the respective root manager's code path.

---

## Why two branches instead of one

`KernelSU-Next` and `SukiSU-Ultra` each implement SUSFS support differently
(different hook mechanisms, different manager-detection/handshake code,
incompatible driver layouts under `drivers/kernelsu`). Rather than fork a
single implementation, this repo tracks both upstream projects independently
so users can pick whichever manager app they prefer, while getting the same
device tree, defconfig, and SUSFS feature set either way.

A `post-checkout` git hook runs [`select-kernelsu.sh`](select-kernelsu.sh)
on every branch switch to re-point `kernel-5.10/drivers/kernelsu` at the
correct source (`KernelSU-Next` submodule on `main`, plain-cloned
`KernelSU` on `susfs-dev`), since Git doesn't track that symlink across
branches on its own.

---

## Build pipeline

```
kernel_builder.yml  (GitHub Actions, matrix: main + susfs-dev)
        │
        ├─ checkout branch
        ├─ scripts/build-main.sh  or  scripts/build-susfs-dev.sh
        │        │
        │        ├─ 1. sync KSU source (fetch dev-susfs branch / run
        │        │      sync-manager-detection.sh against upstream SukiSU-Ultra)
        │        ├─ 2. ./build.sh            (actual kernel compile + packaging)
        │        ├─ 3. read the real .config/Makefile the build produced
        │        │      — never hardcode feature claims
        │        └─ 4. write build-info.env + GitHub Actions outputs
        │
        ├─ create GitHub Release (tag + changelog table from build-info.env)
        └─ send Telegram build card (scripts/lib-telegram.sh)
```

### `build.sh`
Branch-agnostic. Installs toolchain/dependencies, patches
`gen_build_config.py` for Python 3, generates the build config, compiles the
kernel, builds `boot.img`, and zips the final package into `dist/`. The
output filename prefix (`KernelSU-NEXT-...` vs `SukiSU-Ultra-...`) is
controlled by the `PACKAGE_PREFIX` env var set by whichever branch script
calls it, so the artifact name always matches the branch's actual root
manager. The A16 uses a single boot-image layout: `boot.img` is produced
directly and no separate vendor boot image is built.

### Networking and runtime support

Both branches enable the same built-in device-facing features:

- CAKE, FQ and FQ-CoDel queue disciplines, plus ingress and traffic actions
  for tethering and mobile-link QoS.
- Upstream Linux 5.10 BBRv1 with FQ as the default queue discipline.
- WireGuard built into the kernel.
- The upstream NTSYNC interface (`/dev/ntsync`) backported from Linux 6.14
  for Wine/Proton-compatible NT synchronization primitives.

BBRplus is not advertised for this device: available 5.10 BBRplus patches
target a different TCP private-API layout than Samsung's vendor tree. Keeping
the in-tree BBRv1 avoids applying an unverified transport patch to the boot
kernel.

### `scripts/build-main.sh` / `scripts/build-susfs-dev.sh`
Branch-specific orchestration: update the KSU source, invoke `build.sh`,
verify the resulting `.config` for the real feature set (SuSFS, Manual
Hooks, KPM, Magic Mount, LZ4K/LZ4KD, BBR, CAKE, WireGuard, and NTSYNC), and
hand structured results back to the workflow.

### `scripts/lib-telegram.sh`
Single shared Telegram notifier sourced by both branch scripts, so message
formatting and credential handling live in one place instead of being
duplicated (and drifting) per branch. Reads `BOT_TOKEN` / `CHAT_ID` from the
workflow env (backed by the `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID`
repository secrets).

### `sync-manager-detection.sh`
`susfs-dev` only. Pulls the manager-detection/handshake code from
[SukiSU-Ultra's upstream `main`](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
into this repo's in-tree copy, so manager-app compatibility (hash/size
checks, etc.) stays current without hand-patching.

### Scheduling
`kernel_builder.yml` runs every Monday at 00:00 UTC and on manual dispatch,
building **both** branches in a matrix regardless of which branch the
workflow is dispatched from (GitHub always reads scheduled/dispatched
workflow definitions from the default branch, `main`).

---

## Notifications

Every build sends a Telegram message with the device, kernel version, root
manager + version, active hook type, SUSFS version, and enabled feature
list, followed by a direct download link to the packaged `boot.img` once
the GitHub Release is published. Failed builds get a card with a link to
the failing Actions log instead.

---

## Credits

This project builds on top of, and would not exist without:

- **[SUSFS4KSU](https://gitlab.com/simonpunk/susfs4ksu)** by simonpunk —
  the filesystem/process-hiding layer that makes root detection-resistant.
- **[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)** and
  the **[pershoot `dev-susfs` fork](https://github.com/pershoot/KernelSU-Next)**
  used on `main`.
- **[SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)**, used on
  `susfs-dev`.
- **[KernelSU](https://github.com/tiann/KernelSU)** by tiann — the original
  project both of the above build on.
- **Samsung Open Source** and the stock Galaxy A16 (SM-A165F) kernel source
  this tree is derived from.
- The Android common-kernel `build/` tooling (AOSP) used for kernel/module
  packaging.
- The community toolchain used for cross-compilation, sourced via
  [ravindu644/android_kernel_a165f](https://github.com/ravindu644/android_kernel_a165f).

If you maintain any of the above and want attribution changed or expanded,
open an issue.

---

## Disclaimer

Flashing a custom kernel can brick your device or void your warranty. Know
how to recover via Odin/download mode before flashing anything from this
repo. Builds are provided as-is, with no warranty of fitness for any
purpose.
