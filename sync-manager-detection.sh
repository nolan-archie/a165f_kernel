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

MANAGER_FILES=(
  apk_sign.c
  apk_sign.h
  manager_identity.h
  manager_observer.h
  pkg_observer.c
  throne_tracker.c
  throne_tracker.h
)

echo "[+] Diffing against your current tree..."
CHANGED=0
mkdir -p "$TARGET_DIR/manager"
for f in "${MANAGER_FILES[@]}"; do
  SRC="kernel/manager/$f"
  DST="$TARGET_DIR/manager/$f"
  if [ ! -f "$SRC" ]; then
    echo "    [skip] $f not present upstream"
    continue
  fi
  if [ -f "$DST" ] && diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    echo "    [ok]   $f already up to date"
  else
    cp "$SRC" "$DST"
    echo "    [sync] $f updated"
    CHANGED=1
  fi
done

echo "[+] Ensuring EXPECTED_SIZE/EXPECTED_HASH block is present in Makefile..."
if ! grep -q "EXPECTED_SIZE" "$TARGET_DIR/Makefile"; then
  # Insert right before the KSU_MANAGER_PACKAGE block (or at EOF as fallback)
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
