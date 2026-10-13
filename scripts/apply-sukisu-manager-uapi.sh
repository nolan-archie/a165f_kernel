#!/usr/bin/env bash
# Reapply the SukiSU Manager UAPI compatibility patch after weekly source syncs.
set -euo pipefail

REPO_ROOT="${1:?Usage: $0 <repository-root>}"
PATCH_FILE="$REPO_ROOT/scripts/sukisu-manager-uapi-v5.diff"
VERSION_PATCH_FILE="$REPO_ROOT/scripts/sukisu-version-fallback.diff"
KSU_ROOT="$REPO_ROOT/kernel-5.10/KernelSU/kernel"
HEADER="$KSU_ROOT/include/uapi/supercall.h"
DISPATCH="$KSU_ROOT/supercall/dispatch.c"
KSU_MAKEFILE="$KSU_ROOT/Makefile"

if [[ ! -f "$HEADER" || ! -f "$DISPATCH" || ! -f "$PATCH_FILE" || \
      ! -f "$KSU_MAKEFILE" || ! -f "$VERSION_PATCH_FILE" ]]; then
  echo "[compat] Missing SukiSU UAPI source or compatibility patch." >&2
  exit 1
fi

uapi_version() {
  sed -nE 's/^[[:space:]]*DECLARE\(__u32,[[:space:]]*KERNEL_SU_UAPI_VERSION,[[:space:]]*([0-9]+)\);.*/\1/p' \
    "$HEADER" | head -n1
}

uapi_has_services_event() {
  local version
  version="$(uapi_version)"
  [[ "$version" =~ ^[0-9]+$ ]] || return 1
  (( version >= 5 )) || return 1
  grep -Eq 'DECLARE\(__u32,[[:space:]]*EVENT_SERVICES,[[:space:]]*4\);' "$HEADER" || return 1
  grep -Fq 'case EVENT_SERVICES:' "$DISPATCH" || return 1
}

if uapi_has_services_event; then
  echo "[compat] SukiSU kernel UAPI $(uapi_version) already supports EVENT_SERVICES."
else
  echo "[compat] Applying SukiSU Manager UAPI v5 compatibility patch..."
  if ! git -C "$REPO_ROOT" apply --unidiff-zero --check "$PATCH_FILE"; then
    echo "[compat] Patch no longer matches this SukiSU source; refusing to build an incompatible kernel." >&2
    exit 1
  fi
  git -C "$REPO_ROOT" apply --unidiff-zero "$PATCH_FILE"
fi

if ! uapi_has_services_event; then
  echo "[compat] UAPI v5 EVENT_SERVICES support is still missing after patching." >&2
  exit 1
fi

echo "[compat] Verified SukiSU kernel UAPI $(uapi_version)."

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
