#!/usr/bin/env bash
# select-kernelsu.sh
#
# Runs automatically on every `git switch` / `git checkout` (via the
# post-checkout hook) to make sure kernel-5.10/drivers/kernelsu points at
# the correct su implementation for whichever branch you just landed on.
#
# Why this is needed: kernel-5.10/KernelSU (plain clone, SukiSU-Ultra) and
# kernel-5.10/KernelSU-Next (submodule, pershoot fork) both live outside
# git's tracking / are handled separately from the branch you're on. Git
# switching branches does NOT touch them, so the symlink silently goes
# stale whenever you switch between a SukiSU-Ultra branch and a
# KernelSU-Next branch.
#
# Branch -> implementation mapping (edit if you rename branches):
#   sukisu-ultra  -> kernel-5.10/KernelSU        (fork branch: builtin)
#   main          -> kernel-5.10/KernelSU-Next   (submodule, dev-susfs)
#
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

KERNEL_DIR="kernel-5.10"
SYMLINK_PATH="$KERNEL_DIR/drivers/kernelsu"

BRANCH="$(git branch --show-current)"
echo "[select-kernelsu] Detected branch: ${BRANCH:-<detached HEAD>}"

ensure_sukisu() {
  local src="$KERNEL_DIR/KernelSU"
  if [ ! -d "$src/.git" ]; then
    echo "[select-kernelsu] $src missing or empty — re-cloning from fork (branch: builtin)..."
    rm -rf "$src"
    git clone --branch builtin git@github.com:nolan-archie/SukiSU-Ultra.git "$src"
  fi
  ln -sfn ../KernelSU/kernel "$SYMLINK_PATH"
  echo "[select-kernelsu] Symlinked $SYMLINK_PATH -> ../KernelSU/kernel"
}

ensure_kernelsu_next() {
  local src="$KERNEL_DIR/KernelSU-Next"
  if [ ! -d "$src/.git" ] && [ ! -f "$src/.git" ]; then
    echo "[select-kernelsu] $src missing/uninitialized — initializing submodule..."
    git submodule update --init --recursive "$src"
  fi
  ln -sfn ../KernelSU-Next/kernel "$SYMLINK_PATH"
  echo "[select-kernelsu] Symlinked $SYMLINK_PATH -> ../KernelSU-Next/kernel"
}

case "$BRANCH" in
  sukisu-ultra)
    ensure_sukisu
    ;;
  main)
    ensure_kernelsu_next
    ;;
  *)
    echo "[select-kernelsu] No mapping for branch '$BRANCH' — leaving symlink untouched."
    exit 0
    ;;
esac

# Sanity check: fail loudly now instead of 3 layers deep in a Kconfig error later.
if [ ! -f "$SYMLINK_PATH/Kconfig" ]; then
  echo "[select-kernelsu] ERROR: $SYMLINK_PATH/Kconfig still not found after setup." >&2
  echo "[select-kernelsu] Something is wrong with the source directory contents." >&2
  exit 1
fi

echo "[select-kernelsu] OK — Kconfig verified present."
