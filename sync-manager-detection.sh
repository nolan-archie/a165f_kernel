#!/usr/bin/env bash
# sync-manager-detection.sh
#
# Keeps the manager/UAPI layer in sync with SukiSU-Ultra main, while taking the
# throne tracker and signature fallback from builtin-new. The existing kernel
# tree keeps its SUSFS integration and legacy manual-hook implementation.
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
git sparse-checkout set uapi kernel/manager kernel/include kernel/infra kernel/supercall >/dev/null 2>&1
git checkout -q origin/main -- uapi kernel/manager kernel/include kernel/infra kernel/supercall 2>/dev/null || \
  git checkout -q main -- uapi kernel/manager kernel/include kernel/infra kernel/supercall

MANAGER_FILES=(
  apk_sign.c
  apk_sign.h
  dynamic_manager.c
  dynamic_manager.h
  manager_identity.h
  manager_observer.h
  pkg_observer.c
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

echo "[+] Syncing builtin-new throne tracker and signature fallback..."
git clone --filter=blob:none --no-checkout --depth=50 --branch=builtin-new \
  https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "$WORK_DIR/builtin-new" >/dev/null 2>&1
cd "$WORK_DIR/builtin-new"
git sparse-checkout init --cone >/dev/null 2>&1
git sparse-checkout set kernel/manager kernel/extension >/dev/null 2>&1
git checkout -q origin/builtin-new -- \
  kernel/manager/throne_tracker.c \
  kernel/manager/throne_tracker.h \
  kernel/extension/dynamic_sig_fallback.c \
  kernel/extension/dynamic_sig_fallback.h 2>/dev/null || \
  git checkout -q HEAD -- \
  kernel/manager/throne_tracker.c \
  kernel/manager/throne_tracker.h \
  kernel/extension/dynamic_sig_fallback.c \
  kernel/extension/dynamic_sig_fallback.h

TRACKER_SOURCE="$WORK_DIR/builtin-new/kernel/manager/throne_tracker.c"
if grep -Fq 'guarded_mutex_lock(&throne_tracker_mutex)' "$TRACKER_SOURCE"; then
  echo "[+] Applying Linux 5.10 mutex compatibility to builtin-new tracker..."
  if ! git -C "$WORK_DIR/builtin-new" apply --check \
       "$ROOT_DIR/scripts/builtin-new-kernel-5.10-compat.patch"; then
    echo "[ERROR] builtin-new throne tracker changed; update the Linux 5.10 compatibility patch." >&2
    exit 1
  fi
  git -C "$WORK_DIR/builtin-new" apply \
    "$ROOT_DIR/scripts/builtin-new-kernel-5.10-compat.patch"
fi

for file in \
  kernel/manager/throne_tracker.c \
  kernel/manager/throne_tracker.h \
  kernel/extension/dynamic_sig_fallback.c \
  kernel/extension/dynamic_sig_fallback.h
do
  SRC="$WORK_DIR/builtin-new/$file"
  DST="$TARGET_DIR/${file#kernel/}"
  if [ ! -f "$SRC" ]; then
    echo "[ERROR] builtin-new source file missing: $file" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$DST")"
  if [ -f "$DST" ] && diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    echo "    [ok]   ${file#kernel/} already matches builtin-new"
  else
    cp "$SRC" "$DST"
    echo "    [sync] ${file#kernel/} updated from builtin-new"
    CHANGED=1
  fi
done
cd "$ROOT_DIR"

echo "[+] Syncing manager UAPI..."
mkdir -p "$TARGET_DIR/include/uapi"
if [ ! -f "$WORK_DIR/repo/uapi/manager.h" ]; then
  echo "[ERROR] upstream uapi/manager.h is missing; refusing to build without the manager UAPI." >&2
  exit 1
fi
if [ -f "$TARGET_DIR/include/uapi/manager.h" ] && \
   diff -q "$WORK_DIR/repo/uapi/manager.h" "$TARGET_DIR/include/uapi/manager.h" >/dev/null 2>&1; then
  echo "    [ok]   include/uapi/manager.h already up to date"
else
  cp "$WORK_DIR/repo/uapi/manager.h" "$TARGET_DIR/include/uapi/manager.h"
  echo "    [sync] include/uapi/manager.h updated"
  CHANGED=1
fi

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

# UAPI v6 adds batched symbol lookup. Prefer syncing its resolver from upstream,
# but keep the known local implementation when a partial upstream checkout omits
# either file. In both cases, verify that the v6 lookup API is present.
RESOLVER_FILES=(
  symbol_resolver.c
  symbol_resolver.h
)
echo "[+] Syncing UAPI symbol resolver..."
mkdir -p "$TARGET_DIR/infra"
resolver_api_present() {
  local source_file="$1"
  local header_file="$2"
  [ -f "$source_file" ] && [ -f "$header_file" ] && \
    grep -Eq 'int([[:space:]]+__nocfi)?[[:space:]]+ksu_lookup_kernel_symbols[[:space:]]*\(' "$source_file" && \
    grep -Eq 'int[[:space:]]+ksu_lookup_kernel_symbols[[:space:]]*\(' "$header_file"
}

UPSTREAM_RESOLVER_C="$WORK_DIR/repo/kernel/infra/symbol_resolver.c"
UPSTREAM_RESOLVER_H="$WORK_DIR/repo/kernel/infra/symbol_resolver.h"
LOCAL_RESOLVER_C="$TARGET_DIR/infra/symbol_resolver.c"
LOCAL_RESOLVER_H="$TARGET_DIR/infra/symbol_resolver.h"
if [ -f "$UPSTREAM_RESOLVER_C" ] && [ -f "$UPSTREAM_RESOLVER_H" ]; then
  if ! resolver_api_present "$UPSTREAM_RESOLVER_C" "$UPSTREAM_RESOLVER_H"; then
    echo "[ERROR] Upstream symbol resolver does not implement the UAPI v6 lookup API." >&2
    exit 1
  fi
  for f in "${RESOLVER_FILES[@]}"; do
    SRC="$WORK_DIR/repo/kernel/infra/$f"
    DST="$TARGET_DIR/infra/$f"
    if [ -f "$DST" ] && diff -q "$SRC" "$DST" >/dev/null 2>&1; then
      echo "    [ok]   infra/$f already up to date"
    else
      cp "$SRC" "$DST"
      echo "    [sync] infra/$f updated"
      CHANGED=1
    fi
  done
else
  echo "    [fallback] upstream resolver pair unavailable; retaining local UAPI v6 resolver"
  if ! resolver_api_present "$LOCAL_RESOLVER_C" "$LOCAL_RESOLVER_H"; then
    echo "[ERROR] Upstream resolver is incomplete and the local resolver lacks the UAPI v6 lookup API." >&2
    exit 1
  fi
fi

if ! grep -Fq '#include "infra/symbol_resolver.c"' "$TARGET_DIR/ksu.c" || \
   ! grep -Fq 'ksu_init_symbol_resolver();' "$TARGET_DIR/ksu.c"; then
  echo "[ERROR] UAPI v6 symbol resolver is not compiled and initialized by ksu.c." >&2
  exit 1
fi

echo "[+] Syncing current upstream UAPI and event handlers..."
UAPI_BEFORE="$(sha256sum "$TARGET_DIR/include/uapi/supercall.h" "$TARGET_DIR/supercall/dispatch.c" | sha256sum)"
python3 "$ROOT_DIR/scripts/sync-sukisu-uapi.py" \
  "$WORK_DIR/repo/uapi/supercall.h" \
  "$WORK_DIR/repo/kernel/supercall/dispatch.c" \
  "$TARGET_DIR/include/uapi/supercall.h" \
  "$TARGET_DIR/supercall/dispatch.c"
UAPI_AFTER="$(sha256sum "$TARGET_DIR/include/uapi/supercall.h" "$TARGET_DIR/supercall/dispatch.c" | sha256sum)"
[ "$UAPI_BEFORE" != "$UAPI_AFTER" ] && CHANGED=1

echo "[+] Ensuring the SukiSU manager package identity is configured..."
if ! grep -Fq 'ccflags-y += -DKSU_PACKAGE_NAME=\"$(KSU_PACKAGE_NAME)\"' "$TARGET_DIR/Makefile" || \
   ! grep -Fq 'ccflags-y += -DKSU_IS_PR_BUILD=$(KSU_IS_PR_BUILD)' "$TARGET_DIR/Makefile"; then
  PACKAGE_BLOCK=$(cat <<'EOF'
KSU_IS_PR_BUILD ?= 0
ifeq ($(KSU_IS_PR_BUILD),0)
KSU_PACKAGE_NAME ?= com.sukisu.ultra
else
KSU_PACKAGE_NAME ?= com.sukisu.ultra.pr
endif

$(info -- KernelSU Manager package name: $(KSU_PACKAGE_NAME))
ccflags-y += -DKSU_PACKAGE_NAME=\"$(KSU_PACKAGE_NAME)\"
ccflags-y += -DKSU_IS_PR_BUILD=$(KSU_IS_PR_BUILD)
EOF
)
  printf '\n%s\n' "$PACKAGE_BLOCK" >> "$TARGET_DIR/Makefile"
  echo "    [sync] KSU_PACKAGE_NAME and KSU_IS_PR_BUILD definitions added"
  CHANGED=1
else
  echo "    [ok]   KSU_PACKAGE_NAME and KSU_IS_PR_BUILD already configured"
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
  echo "      cd <your kernel build root> && ./build_kernel_a16.sh"
else
  echo
  echo "[+] Already fully in sync. Nothing to rebuild."
fi
