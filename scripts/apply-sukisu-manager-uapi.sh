#!/usr/bin/env bash
# Verify that the synced SukiSU UAPI and all of its events are handled.
set -euo pipefail

REPO_ROOT="${1:?Usage: $0 <repository-root>}"
KSU_ROOT="$REPO_ROOT/kernel-5.10/KernelSU/kernel"
HEADER="$KSU_ROOT/include/uapi/supercall.h"
MANAGER_HEADER="$KSU_ROOT/include/uapi/manager.h"
DISPATCH="$KSU_ROOT/supercall/dispatch.c"
UNIFIED_SOURCE="$KSU_ROOT/ksu.c"
POST_FS_DATA_SOURCE="$KSU_ROOT/runtime/ksud.c"
MANAGER_SOURCE="$KSU_ROOT/manager/dynamic_manager.c"
MANAGER_API="$KSU_ROOT/manager/dynamic_manager.h"
KSU_MAKEFILE="$KSU_ROOT/Makefile"
VERSION_PATCH_FILE="$REPO_ROOT/scripts/sukisu-version-fallback.diff"

if [[ ! -f "$HEADER" || ! -f "$MANAGER_HEADER" || ! -f "$DISPATCH" || \
      ! -f "$UNIFIED_SOURCE" || ! -f "$POST_FS_DATA_SOURCE" || \
      ! -f "$MANAGER_SOURCE" || ! -f "$MANAGER_API" || \
      ! -f "$KSU_MAKEFILE" || ! -f "$VERSION_PATCH_FILE" ]]; then
  echo "[compat] Missing SukiSU manager UAPI, implementation, or compatibility support file." >&2
  exit 1
fi

uapi_version() {
  sed -nE 's/^[[:space:]]*DECLARE\(__u32,[[:space:]]*KERNEL_SU_UAPI_VERSION,[[:space:]]*([0-9]+)\);.*/\1/p' \
    "$HEADER" | head -n1
}

version="$(uapi_version)"
if [[ ! "$version" =~ ^[0-9]+$ ]]; then
  echo "[compat] Could not read KERNEL_SU_UAPI_VERSION from the synced header." >&2
  exit 1
fi

mapfile -t events < <(
  sed -nE 's/^[[:space:]]*DECLARE\(__u32,[[:space:]]*(EVENT_[A-Z0-9_]+),.*/\1/p' "$HEADER"
)
if [[ "${#events[@]}" -eq 0 ]]; then
  echo "[compat] No event declarations found in the synced SukiSU UAPI." >&2
  exit 1
fi

for event in "${events[@]}"; do
  if ! grep -Eq "^[[:space:]]*case[[:space:]]+$event[[:space:]]*:" "$DISPATCH"; then
    echo "[compat] UAPI event $event has no kernel handler; refusing to build." >&2
    exit 1
  fi
done

if ! grep -Fq '#include "uapi/manager.h"' "$HEADER" || \
   ! grep -Eq 'DECLARE\(__u32,[[:space:]]*KSU_IOCTL_MANAGER,' "$HEADER" || \
   ! grep -Eq 'struct[[:space:]]+ksu_manager_cmd' "$MANAGER_HEADER"; then
  echo "[compat] Dynamic manager UAPI is incomplete; refusing to build." >&2
  exit 1
fi

if ! grep -Eq 'static[[:space:]]+int[[:space:]]+do_manager\(' "$DISPATCH" || \
   ! grep -Eq '\.cmd[[:space:]]*=[[:space:]]*KSU_IOCTL_MANAGER' "$DISPATCH" || \
   ! grep -Eq '\.handler[[:space:]]*=[[:space:]]*do_manager' "$DISPATCH" || \
   ! grep -Eq '\.perm_check[[:space:]]*=[[:space:]]*manager_or_root' "$DISPATCH"; then
  echo "[compat] KSU_IOCTL_MANAGER is missing its manager-or-root handler; refusing to build." >&2
  exit 1
fi

if ! grep -Fq '#include "manager/dynamic_manager.c"' "$UNIFIED_SOURCE" || \
   ! grep -Fq 'ksu_dynamic_manager_load();' "$POST_FS_DATA_SOURCE"; then
  echo "[compat] Dynamic manager implementation is not linked or loaded at post-fs-data; refusing to build." >&2
  exit 1
fi

while IFS= read -r event; do
  if ! printf '%s\n' "${events[@]}" | grep -Fxq "$event"; then
    echo "[compat] Kernel handles undeclared event $event; refusing to build." >&2
    exit 1
  fi
done < <(sed -nE 's/^[[:space:]]*case[[:space:]]+(EVENT_[A-Z0-9_]+)[[:space:]]*:.*/\1/p' "$DISPATCH")

if [[ -f "$UNIFIED_SOURCE" ]]; then
  if [[ ! -f "$KSU_ROOT/include/uapi/extension.h" || \
        ! -f "$KSU_ROOT/extension/extension.c" || \
        ! -f "$KSU_ROOT/extension/cpu_spoof.c" || \
        ! -f "$KSU_ROOT/extension/dynamic_manager_ext.c" || \
        ! -f "$KSU_ROOT/extension/kpm.c" || \
        ! -f "$KSU_ROOT/extension/susfs_extension.c" || \
        ! -f "$KSU_ROOT/extension/umount_paths.c" || \
        ! -f "$KSU_ROOT/extension/version_spoof.c" || \
        ! -f "$KSU_ROOT/feature/shell_su_adb_only.c" || \
        ! -f "$KSU_ROOT/feature/susfs_features.c" ]]; then
    echo "[compat] SukiSU extension hub or legacy feature adapters are incomplete; refusing to build." >&2
    exit 1
  fi
  if ! grep -Eq '\.cmd[[:space:]]*=[[:space:]]*KSU_IOCTL_EXTENSION' "$DISPATCH" || \
     ! grep -Eq '\.handler[[:space:]]*=[[:space:]]*do_extension' "$DISPATCH" || \
     ! grep -Fq '#include "extension/extension.c"' "$UNIFIED_SOURCE" || \
     ! grep -Fq '#include "extension/dynamic_manager_ext.c"' "$UNIFIED_SOURCE" || \
     ! grep -Fq 'ksu_extension_register_all();' "$UNIFIED_SOURCE" || \
     ! grep -Fq 'ksu_shell_su_adb_only_init();' "$UNIFIED_SOURCE" || \
     ! grep -Fq 'ksu_extension_apply_forced();' "$POST_FS_DATA_SOURCE" || \
     ! grep -Fq 'KSU_FEATURE_MOUNT_HIDE' "$KSU_ROOT/feature/susfs_features.c" || \
     ! grep -Fq 'KSU_FEATURE_AVC_SPOOF' "$KSU_ROOT/feature/susfs_features.c"; then
    echo "[compat] SukiSU extension hub or legacy feature adapters are not wired into the kernel." >&2
    exit 1
  fi
  echo "[compat] Verified extension hub and shell/SuSFS feature handlers."
fi

echo "[compat] Verified SukiSU kernel UAPI $version, dynamic manager ioctl, and ${#events[@]} handled events."

version_fallback() {
  sed -nE 's/^[[:space:]]*KSU_VERSION_FALLBACK[[:space:]]*\?=[[:space:]]*([0-9]+).*/\1/p' \
    "$KSU_MAKEFILE" | head -n1
}

fallback="$(version_fallback)"
if [[ "$fallback" =~ ^[0-9]+$ ]] && (( fallback >= 40968 )) && \
   grep -Fq 'KSU_VERSION_FALLBACK))' "$KSU_MAKEFILE"; then
  echo "[compat] SukiSU offline version fallback is $fallback."
else
  echo "[compat] Applying manager-compatible SukiSU version fallback..."
  if ! git -C "$REPO_ROOT" apply --unidiff-zero --check "$VERSION_PATCH_FILE"; then
    echo "[compat] Version fallback patch no longer matches this SukiSU source." >&2
    exit 1
  fi
  git -C "$REPO_ROOT" apply --unidiff-zero "$VERSION_PATCH_FILE"
  fallback="$(version_fallback)"
  if [[ ! "$fallback" =~ ^[0-9]+$ ]] || (( fallback < 40968 )) || \
     ! grep -Fq 'KSU_VERSION_FALLBACK))' "$KSU_MAKEFILE"; then
    echo "[compat] SukiSU version fallback is still below the installed manager." >&2
    exit 1
  fi
  echo "[compat] Verified SukiSU offline version fallback is $fallback."
fi

if ! grep -Fq 'ccflags-y += -DKSU_PACKAGE_NAME=\"$(KSU_PACKAGE_NAME)\"' "$KSU_MAKEFILE" || \
   ! grep -Fq 'ccflags-y += -DKSU_IS_PR_BUILD=$(KSU_IS_PR_BUILD)' "$KSU_MAKEFILE" || \
   ! grep -Eq 'KSU_PACKAGE_NAME[[:space:]]*\?=[[:space:]]*com\.sukisu\.ultra([[:space:]]|$)' "$KSU_MAKEFILE"; then
  echo "[compat] SukiSU manager package identity is not configured in the kernel Makefile." >&2
  exit 1
fi
echo "[compat] Verified SukiSU manager package identity compile flags."
