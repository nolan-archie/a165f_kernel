#!/usr/bin/env bash
# sync-manager-detection.sh
#
# Keeps the KERNEL-SIDE manager-detection code and UAPI in your builtin-based
# tree in sync with SukiSU-Ultra's main branch.
#
# Usage:
#   ./sync-manager-detection.sh /path/to/your/a165f_kernel/kernel-5.10/drivers/kernelsu
#
set -euo pipefail

TARGET_DIR="${1:?Usage: $0 <path-to-drivers/kernelsu>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ ! -f "$TARGET_DIR/Makefile" ]; then
  echo "[ERROR] $TARGET_DIR/Makefile not found. Point this at drivers/kernelsu." >&2
  exit 1
fi

echo "[+] Fetching upstream main (manager and UAPI sources, shallow)..."
git clone --filter=blob:none --no-checkout --depth=50 \
  https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "$WORK_DIR/repo" >/dev/null 2>&1
cd "$WORK_DIR/repo"
git sparse-checkout init --cone >/dev/null 2>&1
git sparse-checkout set uapi kernel/manager kernel/include kernel/supercall >/dev/null 2>&1
git checkout -q origin/main -- uapi kernel/manager kernel/include kernel/supercall 2>/dev/null || \
  git checkout -q main -- uapi kernel/manager kernel/include kernel/supercall

MANAGER_FILES=(
  apk_sign.c
  apk_sign.h
  manager_identity.h
  manager_observer.h
  pkg_observer.c
  throne_tracker.c
  throne_tracker.h
)

echo "[+] Diffing against your current tree (from upstream main)..."
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

# kernel/include/*.h files that manager/ sources depend on via quoted
# includes. The synced manager files include util.h, which also includes
# arch.h, so keep both headers in sync with the upstream manager sources.
INCLUDE_FILES=(
  arch.h
  util.h
)

echo "[+] Diffing manager's kernel/include dependencies against your current tree..."
mkdir -p "$TARGET_DIR/include"
for f in "${INCLUDE_FILES[@]}"; do
  SRC="kernel/include/$f"
  DST="$TARGET_DIR/include/$f"
  if [ ! -f "$SRC" ]; then
    echo "    [skip] include/$f not present upstream"
    continue
  fi
  if [ -f "$DST" ] && diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    echo "    [ok]   include/$f already up to date"
  else
    cp "$SRC" "$DST"
    echo "    [sync] include/$f updated"
    CHANGED=1
  fi
done

echo "[+] Syncing current upstream UAPI and event handlers..."
UAPI_BEFORE="$(sha256sum "$TARGET_DIR/include/uapi/supercall.h" "$TARGET_DIR/supercall/dispatch.c" | sha256sum)"
python3 "$ROOT_DIR/scripts/sync-sukisu-uapi.py" \
  "$WORK_DIR/repo/uapi/supercall.h" \
  "$WORK_DIR/repo/kernel/supercall/dispatch.c" \
  "$TARGET_DIR/include/uapi/supercall.h" \
  "$TARGET_DIR/supercall/dispatch.c"
UAPI_AFTER="$(sha256sum "$TARGET_DIR/include/uapi/supercall.h" "$TARGET_DIR/supercall/dispatch.c" | sha256sum)"
[ "$UAPI_BEFORE" != "$UAPI_AFTER" ] && CHANGED=1

echo "[+] Fetching your fork's builtin branch (source of truth for pkg_observer.h / pkg_observer_compat.h)..."
git clone --filter=blob:none --no-checkout --depth=50 --branch=builtin \
  https://github.com/nolan-archie/SukiSU-Ultra.git "$WORK_DIR/fork" >/dev/null 2>&1
cd "$WORK_DIR/fork"
git sparse-checkout init --cone >/dev/null 2>&1
git sparse-checkout set kernel/manager >/dev/null 2>&1
git checkout -q origin/builtin -- kernel/manager 2>/dev/null || git checkout -q HEAD -- kernel/manager

# Debug: list what we actually got
echo "    [dbg]  Files in fork checkout:"
for f in kernel/manager/*; do
  [ -f "$f" ] && echo "           $(basename "$f")"
done

for f in pkg_observer.h pkg_observer_compat.h; do
  SRC="kernel/manager/$f"
  DST="$TARGET_DIR/manager/$f"
  if [ ! -f "$SRC" ]; then
    echo "[ERROR] $f not found in builtin fork checkout at $SRC" >&2
    exit 1
  fi
  if [ -f "$DST" ] && diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    echo "    [ok]   $f already up to date"
  else
    cp "$SRC" "$DST"
    echo "    [sync] $f updated (from builtin fork)"
    CHANGED=1
  fi
done

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
  echo "      cd <your kernel build root> && ./build_kernel_a16.sh"
else
  echo
  echo "[+] Already fully in sync. Nothing to rebuild."
fi
