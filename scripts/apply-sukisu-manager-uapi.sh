#!/usr/bin/env bash
# Verify that the synced SukiSU UAPI and all of its events are handled.
set -euo pipefail

REPO_ROOT="${1:?Usage: $0 <repository-root>}"
KSU_ROOT="$REPO_ROOT/kernel-5.10/KernelSU/kernel"
HEADER="$KSU_ROOT/include/uapi/supercall.h"
DISPATCH="$KSU_ROOT/supercall/dispatch.c"
KSU_MAKEFILE="$KSU_ROOT/Makefile"
VERSION_PATCH_FILE="$REPO_ROOT/scripts/sukisu-version-fallback.diff"

if [[ ! -f "$HEADER" || ! -f "$DISPATCH" || ! -f "$KSU_MAKEFILE" || \
      ! -f "$VERSION_PATCH_FILE" ]]; then
  echo "[compat] Missing SukiSU UAPI source or compatibility support file." >&2
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

while IFS= read -r event; do
  if ! printf '%s\n' "${events[@]}" | grep -Fxq "$event"; then
    echo "[compat] Kernel handles undeclared event $event; refusing to build." >&2
    exit 1
  fi
done < <(sed -nE 's/^[[:space:]]*case[[:space:]]+(EVENT_[A-Z0-9_]+)[[:space:]]*:.*/\1/p' "$DISPATCH")

echo "[compat] Verified SukiSU kernel UAPI $version with ${#events[@]} handled events."

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
