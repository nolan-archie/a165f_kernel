#!/usr/bin/env bash
# Sync the vendored SukiSU Nova kernel source to the reviewed builtin-new pin.
# The Codeberg mirror is used when the announced primary cannot provide it.
# This script never commits or pushes changes.

set -euo pipefail

TARGET_DIR="${1:?Usage: $0 <path-to-drivers/kernelsu> }"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/sukisu-upstream.env"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TRACKER_PATCH="$ROOT_DIR/scripts/builtin-new-kernel-5.10-compat.patch"
VERSION_PATCH="$ROOT_DIR/scripts/builtin-new-build-version.patch"
SUSFS_PATCH="$ROOT_DIR/scripts/builtin-new-susfs-v2.3-compat.patch"
PATH_ABI_APPLIER="$ROOT_DIR/scripts/apply-sukisu-susfs-5.10-path-abi.py"

if [[ ! -f "$TARGET_DIR/Makefile" ]]; then
  echo "[ERROR] $TARGET_DIR/Makefile not found; expected the kernelsu source directory." >&2
  exit 1
fi
TARGET_DIR="$(realpath "$TARGET_DIR")"
KSU_ROOT="$(dirname "$TARGET_DIR")"

tree_hash() {
  (
    cd "$TARGET_DIR"
    find . -type f -print0 | sort -z | xargs -0 -r sha256sum
  ) | sha256sum | awk '{print $1}'
}

clone_pinned_source() {
  local url="$1"
  git clone --filter=blob:none --no-checkout --single-branch \
    --branch "$SUKISU_BRANCH" "$url" "$WORK_DIR/upstream" >/dev/null 2>&1 || return 1

  if ! git -C "$WORK_DIR/upstream" cat-file -e "$SUKISU_COMMIT^{commit}" 2>/dev/null; then
    git -C "$WORK_DIR/upstream" fetch --quiet --no-tags origin "$SUKISU_COMMIT" || return 1
  fi
  git -C "$WORK_DIR/upstream" checkout --quiet --detach "$SUKISU_COMMIT" || return 1
  SOURCE_URL="$url"
}

SOURCE_URL=""
if ! clone_pinned_source "$SUKISU_PRIMARY_URL"; then
  rm -rf "$WORK_DIR/upstream"
  echo "[sync] Primary did not provide $SUKISU_COMMIT; using Codeberg mirror."
  clone_pinned_source "$SUKISU_MIRROR_URL" || {
    echo "[ERROR] Could not fetch SukiSU Nova $SUKISU_BRANCH at $SUKISU_COMMIT from either source." >&2
    exit 1
  }
fi

UPSTREAM_DIR="$WORK_DIR/upstream/kernel"
for required in Kconfig Makefile ksu.c include/uapi/supercall.h manager/throne_tracker.c; do
  if [[ ! -f "$UPSTREAM_DIR/$required" ]]; then
    echo "[ERROR] Pinned SukiSU source is missing kernel/$required." >&2
    exit 1
  fi
done

# SukiSU's builtin-new tracker uses guarded_mutex_lock(), unavailable in this
# device's Linux 5.10 tree. Keep the reviewed compatibility patch when needed.
TRACKER="$UPSTREAM_DIR/manager/throne_tracker.c"
if grep -Fq 'guarded_mutex_lock(&throne_tracker_mutex)' "$TRACKER"; then
  git -C "$WORK_DIR/upstream" apply --check "$TRACKER_PATCH" || {
    echo "[ERROR] Linux 5.10 tracker compatibility patch no longer applies." >&2
    exit 1
  }
  git -C "$WORK_DIR/upstream" apply "$TRACKER_PATCH"
fi

# Use the reviewed pin in the kernel version string even when the vendored
# checkout is built from a detached source snapshot with no nested .git.
if ! grep -Fq 'KSU_BUILD_COMMIT' "$UPSTREAM_DIR/Makefile" || \
   ! grep -Fq 'REPO_BRANCH := builtin-new' "$UPSTREAM_DIR/Makefile"; then
  git -C "$WORK_DIR/upstream" apply --check "$VERSION_PATCH" || {
    echo "[ERROR] Pinned build-version patch no longer applies." >&2
    exit 1
  }
  git -C "$WORK_DIR/upstream" apply "$VERSION_PATCH"
fi

# The local SUSFS v2.3.0 tree predates builtin-new's optional UID-filter
# commands and v2.4 native SELinux tables. Guard those unavailable APIs and
# retain the legacy backup-policy query path for the local SELinux integration.
if ! grep -Fq 'defined(CMD_SUSFS_SET_PRIORITY_UID_FILTER)' "$UPSTREAM_DIR/manager/pkg_observer.c" || \
   ! grep -Fq 'defined(CMD_SUSFS_SET_SUS_PATH_UID_FILTER)' "$UPSTREAM_DIR/manager/pkg_observer.c" || \
   ! grep -Fq '#ifdef CMD_SUSFS_SET_SUS_PATH_UID_FILTER' "$UPSTREAM_DIR/supercall/supercall.c" || \
   ! grep -Fq '#ifdef CMD_SUSFS_SET_PRIORITY_UID_FILTER' "$UPSTREAM_DIR/supercall/supercall.c" || \
   ! grep -Fq 'CONFIG_KSU_SUSFS_V24_SELINUX_TABLES' "$UPSTREAM_DIR/selinux/sepolicy.c" || \
   ! grep -Fq 'struct selinux_policy *backup_sepolicy;' "$UPSTREAM_DIR/selinux/rules.c" || \
   ! grep -Fq 'extern bool ksu_selinux_hide_enabled __read_mostly;' "$UPSTREAM_DIR/downstream/slow_avc_audit_defs.h" || \
   ! grep -Fq 'bool ksu_selinux_hide_enabled __read_mostly = true;' "$UPSTREAM_DIR/feature/selinux_hide.c" || \
   ! grep -Fq 'bool ksu_selinux_hide_enabled __read_mostly;' "$UPSTREAM_DIR/feature/selinux_hide_arm64.c"; then
  git -C "$WORK_DIR/upstream" apply --check "$SUSFS_PATCH" || {
    echo "[ERROR] SUSFS v2.3.0 compatibility patch no longer applies." >&2
    exit 1
  }
  git -C "$WORK_DIR/upstream" apply "$SUSFS_PATCH"
fi

# Linux 5.10's fs/open.c and fs/stat.c SUSFS hooks pass const char __user **
# before user_path_at(). builtin-new's struct filename ** handlers are for a
# different call-site ABI and can fault when those pathname syscalls run.
if ! grep -Fq 'The 5.10 SUSFS call sites run before user_path_at()' \
     "$UPSTREAM_DIR/feature/sucompat.c"; then
  python3 "$PATH_ABI_APPLIER" "$UPSTREAM_DIR/feature/sucompat.c" || {
    echo "[ERROR] Linux 5.10 SUSFS pathname ABI adaptation failed; review upstream." >&2
    exit 1
  }
fi

BEFORE_HASH="$(tree_hash)"
rsync -a --delete \
  --exclude='/.clang-format' \
  --exclude='/.clangd' \
  --exclude='/.gitignore' \
  "$UPSTREAM_DIR/" "$TARGET_DIR/"
cp "$WORK_DIR/upstream/LICENSE" "$KSU_ROOT/LICENSE"
cp "$WORK_DIR/upstream/.gitignore" "$KSU_ROOT/.gitignore"
AFTER_HASH="$(tree_hash)"

# This checkout carried a nested clone of the old fork. Keep its local origin
# aligned with the source used for this vendored tree, without changing files.
if [[ -d "$KSU_ROOT/.git" ]] && git -C "$KSU_ROOT" remote get-url origin >/dev/null 2>&1; then
  git -C "$KSU_ROOT" remote set-url origin "$SOURCE_URL"
fi

if [[ "$BEFORE_HASH" == "$AFTER_HASH" ]]; then
  CHANGED=0
  echo "[sync] SukiSU Nova $SUKISU_BRANCH is already at $SUKISU_COMMIT with local compatibility patches."
else
  CHANGED=1
  echo "[sync] Vendored SukiSU Nova $SUKISU_BRANCH at $SUKISU_COMMIT."
fi

echo "CHANGED=$CHANGED" >> "${GITHUB_OUTPUT:-/dev/stdout}"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "KSU_BUILD_REF=$SUKISU_BRANCH" >> "$GITHUB_ENV"
  echo "KSU_BUILD_COMMIT=$SUKISU_COMMIT" >> "$GITHUB_ENV"
fi
