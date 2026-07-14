#!/usr/bin/env bash
# sync-manager-detection.sh
#
# Keeps the KERNEL-SIDE manager-detection code (apk_sign.c, throne_tracker.c,
# manager_identity.h, etc.) in your builtin-based tree in sync with
# SukiSU-Ultra's `main` branch, WITHOUT trying to merge the two unrelated
# histories or touch anything SUSFS-related.
#
# Why this is safe: the manager subsystem is self-contained (kernel/manager/*
# + the EXPECTED_SIZE/EXPECTED_HASH block in kernel/Makefile). It doesn't
# depend on the hook/selinux rewrite that makes `main` and `builtin`
# incompatible everywhere else.
#
# CHANGED FROM THE ORIGINAL: this version syncs the WHOLE kernel/manager/
# directory instead of a hardcoded file list. The hardcoded list silently
# missed pkg_observer.h when upstream added it, which broke the build
# (ksu.c couldn't find it). Whole-directory sync means a future upstream
# file addition can't cause that same class of failure again.
#
# Usage:
#   ./sync-manager-detection.sh /path/to/your/a165f_kernel/kernel-5.10/drivers/kernelsu
#
set -euo pipefail

TARGET_DIR="${1:?Usage: $0 <path-to-drivers/kernelsu>}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ ! -f "$TARGET_DIR/Makefile" ]; then
  echo "[ERROR] $TARGET_DIR/Makefile not found. Point this at drivers/kernelsu." >&2
  exit 1
fi

echo "[+] Fetching upstream main (manager files only, shallow)..."
git clone --filter=blob:none --no-checkout --depth=50 \
  https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "$WORK_DIR/repo" >/dev/null 2>&1
cd "$WORK_DIR/repo"
git sparse-checkout init --cone >/dev/null 2>&1
git sparse-checkout set kernel/manager >/dev/null 2>&1
git checkout -q origin/main -- kernel/manager 2>/dev/null || git checkout -q main -- kernel/manager

if [ ! -d "kernel/manager" ]; then
  echo "[ERROR] kernel/manager not found upstream after checkout — aborting, not touching your tree." >&2
  exit 1
fi

echo "[+] Syncing entire kernel/manager/ directory (not a fixed file list)..."
mkdir -p "$TARGET_DIR/manager"

# rsync -c (checksum) so "changed" reflects real content diffs, not just
# mtimes, and --delete so files removed upstream get removed here too.
if command -v rsync >/dev/null 2>&1; then
  RSYNC_OUT="$(rsync -ac --delete --out-format="%n" "kernel/manager/" "$TARGET_DIR/manager/")"
  if [ -n "$RSYNC_OUT" ]; then
    echo "$RSYNC_OUT" | sed 's/^/    [sync] /'
    CHANGED=1
  else
    echo "    [ok]   manager/ already fully in sync"
    CHANGED=0
  fi
else
  # Fallback if rsync isn't available: plain copy + diff-based change detection
  BEFORE_HASH="$(find "$TARGET_DIR/manager" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum || echo none)"
  cp -rf kernel/manager/. "$TARGET_DIR/manager/"
  AFTER_HASH="$(find "$TARGET_DIR/manager" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum || echo none)"
  CHANGED=0
  [ "$BEFORE_HASH" != "$AFTER_HASH" ] && CHANGED=1
  echo "    [sync] copied kernel/manager/ -> $TARGET_DIR/manager/ (changed=$CHANGED)"
fi

echo "[+] Ensuring EXPECTED_SIZE/EXPECTED_HASH block is present in Makefile..."
if ! grep -q "EXPECTED_SIZE" "$TARGET_DIR/Makefile"; then
  BLOCK=$(cat <<'EOF'
ifndef KSU_EXPECTED_SIZE
KSU_EXPECTED_SIZE := 0x35c
endif

ifndef KSU_EXPECTED_HASH
KSU_EXPECTED_HASH := 947ae944f3de4ed4c21a7e4f7953ecf351bfa2b36239da37a34111ad29993eef
endif

$(info -- KernelSU Manager signature size: $(KSU_EXPECTED_SIZE))
$(info -- KernelSU Manager signature hash: $(KSU_EXPECTED_HASH))

ccflags-y += -DEXPECTED_SIZE=$(KSU_EXPECTED_SIZE)
ccflags-y += -DEXPECTED_HASH=\"$(KSU_EXPECTED_HASH)\"

ifdef KSU_EXPECTED_SIZE2
ifndef KSU_EXPECTED_HASH2
$(error KSU_EXPECTED_HASH2 must be set when KSU_EXPECTED_SIZE2 is set)
endif
ccflags-y += -DEXPECTED_SIZE2=$(KSU_EXPECTED_SIZE2)
ccflags-y += -DEXPECTED_HASH2=\"$(KSU_EXPECTED_HASH2)\"
endif
EOF
)
  if grep -q "^ifdef KSU_MANAGER_PACKAGE$" "$TARGET_DIR/Makefile"; then
    awk -v block="$BLOCK" '
      /^ifdef KSU_MANAGER_PACKAGE$/ && !done { print block; print ""; done=1 }
      { print }
    ' "$TARGET_DIR/Makefile" > "$TARGET_DIR/Makefile.new"
    mv "$TARGET_DIR/Makefile.new" "$TARGET_DIR/Makefile"
  else
    printf '\n%s\n' "$BLOCK" >> "$TARGET_DIR/Makefile"
  fi
  echo "    [sync] EXPECTED_SIZE/HASH block inserted into Makefile"
  CHANGED=1
else
  echo "    [ok]   EXPECTED_SIZE/HASH block already present"
fi

if [ "$CHANGED" -eq 1 ]; then
  echo
  echo "[+] Done. Files changed — rebuild your kernel now:"
  echo "      cd <your kernel build root> && ./build_kernel_a16.sh   # or your build command"
else
  echo
  echo "[+] Already fully in sync. Nothing to rebuild."
fi
