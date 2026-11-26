#!/usr/bin/env bash
# Sync the pinned SukiSU Nova source and verify SuSFS symbols on this checkout.
# This intentionally does not switch branches, update SUSFS core files, or
# touch the KernelSU-Next submodule used by main.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="${1:-$ROOT_DIR}"
VERIFY="$SCRIPT_DIR/verify-susfs-symbols.sh"
SYNC="$ROOT_DIR/sync-manager-detection.sh"
COMPAT="$SCRIPT_DIR/apply-sukisu-manager-uapi.sh"
KERNEL_DIR="$REPO/kernel-5.10"
KSU_DIR="$KERNEL_DIR/drivers/kernelsu"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] $REPO is not a Git worktree." >&2
  exit 1
fi
if [[ "$(git -C "$REPO" branch --show-current)" != "susfs-dev-builtin-new" && \
      "$(git -C "$REPO" branch --show-current)" != "susfs-dev" ]]; then
  echo "[ERROR] Run this on susfs-dev or susfs-dev-builtin-new; it never changes branches." >&2
  exit 1
fi
for file in "$VERIFY" "$SYNC" "$COMPAT"; do
  [[ -f "$file" ]] || { echo "[ERROR] Required helper missing: $file" >&2; exit 1; }
done
[[ -e "$KSU_DIR/Makefile" ]] || {
  echo "[ERROR] $KSU_DIR/Makefile is missing; the kernelsu symlink/source is not wired." >&2
  exit 1
}

echo "[+] Syncing pinned SukiSU Nova builtin-new source..."
bash "$SYNC" "$KSU_DIR"
echo "[+] Checking the manager/UAPI integration..."
bash "$COMPAT" "$REPO"
echo "[+] Verifying SuSFS symbols..."
bash "$VERIFY" "$KERNEL_DIR" "$KSU_DIR"
echo "[+] Pinned SukiSU Nova source and SuSFS symbol checks passed."
