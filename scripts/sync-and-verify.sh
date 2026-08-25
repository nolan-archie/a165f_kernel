#!/usr/bin/env bash
# sync-and-verify.sh
#
# Updates BOTH branches (main, susfs-dev) to their latest upstream sources,
# then runs verify-susfs-symbols.sh against each before you spend a build
# cycle finding out the hard way. Mirrors the style of the existing
# sync-manager-detection.sh (shallow sparse clones to a temp dir, diff-based
# "what changed" reporting).
#
# REQUIRES NETWORK ACCESS TO gitlab.com AND github.com.
# Run this on your machine or in the GitHub Actions runner -- it will NOT
# run inside a sandboxed assistant environment that only allow-lists
# github.com (gitlab.com fetches will hard-fail with host_not_allowed).
#
# Usage:
#   ./sync-and-verify.sh /path/to/a165f_kernel
#
# What it does, per branch:
#   main (KernelSU-Next / pershoot dev-susfs):
#     - git submodule update --remote to bump the pin to latest dev-susfs
#     - refresh kernel-5.10/include/linux/susfs.h, susfs_def.h, fs/susfs.c
#       from simonpunk/susfs4ksu gki-android12-5.10-dev (matches this
#       repo's kernel version; the KernelSU-Next side is what actually
#       calls into these -- see build 32677869245 postmortem)
#     - run select-kernelsu.sh equivalent to point drivers/kernelsu at
#       KernelSU-Next
#     - run verify-susfs-symbols.sh
#
#   susfs-dev (SukiSU-Ultra / builtin fork):
#     - pull latest nolan-archie/SukiSU-Ultra builtin branch
#     - refresh the same three core susfs files from simonpunk upstream
#     - point drivers/kernelsu at KernelSU (SukiSU-Ultra)
#     - run verify-susfs-symbols.sh
#
# It does NOT attempt a full kernel compile -- no Android GKI toolchain is
# assumed to be present. verify-susfs-symbols.sh is a static stand-in that
# catches the specific class of bug that broke build 32677869245
# (susfs_* symbols called but never declared/defined in scope) without
# needing the real build environment. Treat a clean run here as "safe to
# kick off a real build", not "guaranteed to build" -- it only covers that
# one bug class.
#
set -euo pipefail

REPO="${1:?Usage: $0 /path/to/a165f_kernel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="$SCRIPT_DIR/verify-susfs-symbols.sh"

if [ ! -f "$VERIFY" ]; then
  echo "[ERROR] verify-susfs-symbols.sh not found next to this script." >&2
  exit 1
fi
if [ ! -d "$REPO/.git" ]; then
  echo "[ERROR] $REPO is not a git repo." >&2
  exit 1
fi

SUSFS_UPSTREAM_URL="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_UPSTREAM_BRANCH="gki-android12-5.10-dev"
SUKISU_FORK_URL="https://github.com/nolan-archie/SukiSU-Ultra.git"
SUKISU_FORK_BRANCH="builtin"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

RESULTS=()

refresh_susfs_core() {
  # Copies the three core files from simonpunk's tree into $1/kernel-5.10.
  local target_kdir="$1"
  local sparse_dir="$WORK_DIR/susfs4ksu"
  if [ ! -d "$sparse_dir" ]; then
    echo "[+] Fetching simonpunk/susfs4ksu ($SUSFS_UPSTREAM_BRANCH, shallow sparse)..."
    git clone --filter=blob:none --no-checkout --depth=20 \
      --branch "$SUSFS_UPSTREAM_BRANCH" "$SUSFS_UPSTREAM_URL" "$sparse_dir" >/dev/null 2>&1
    (
      cd "$sparse_dir"
      git sparse-checkout init --cone >/dev/null 2>&1
      git sparse-checkout set kernel_patches/fs kernel_patches/include/linux >/dev/null 2>&1
      git checkout -q "$SUSFS_UPSTREAM_BRANCH" >/dev/null 2>&1
    )
  fi

  local pairs=(
    "kernel_patches/fs/susfs.c:fs/susfs.c"
    "kernel_patches/include/linux/susfs.h:include/linux/susfs.h"
    "kernel_patches/include/linux/susfs_def.h:include/linux/susfs_def.h"
  )
  local changed=0
  for pair in "${pairs[@]}"; do
    local src="$sparse_dir/${pair%%:*}"
    local dst="$target_kdir/${pair##*:}"
    if [ ! -f "$src" ]; then
      echo "    [ERROR] $src not found upstream -- layout may have changed, check manually." >&2
      continue
    fi
    if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null 2>&1; then
      echo "    [ok]   $(basename "$dst") already up to date"
    else
      cp "$src" "$dst"
      echo "    [sync] $(basename "$dst") updated"
      changed=1
    fi
  done
  return $changed
}

process_branch() {
  local branch="$1"
  echo
  echo "======================================================================"
  echo " Branch: $branch"
  echo "======================================================================"

  git -C "$REPO" checkout -q "$branch"
  git -C "$REPO" pull -q origin "$branch"

  echo "[+] Refreshing SUSFS core files from upstream..."
  refresh_susfs_core "$REPO/kernel-5.10" || true

  local ksu_dir="$REPO/kernel-5.10/drivers/kernelsu"

  if [ "$branch" = "main" ]; then
    echo "[+] Bumping KernelSU-Next submodule to latest dev-susfs..."
    git -C "$REPO" submodule update --init --remote kernel-5.10/KernelSU-Next
    ln -sfn ../KernelSU-Next/kernel "$ksu_dir"
  elif [ "$branch" = "susfs-dev" ]; then
    echo "[+] Refreshing SukiSU-Ultra ($SUKISU_FORK_BRANCH) plain clone..."
    local sukisu_dir="$REPO/kernel-5.10/KernelSU"
    if [ -d "$sukisu_dir/.git" ]; then
      git -C "$sukisu_dir" fetch -q origin "$SUKISU_FORK_BRANCH"
      git -C "$sukisu_dir" reset -q --hard "origin/$SUKISU_FORK_BRANCH"
    else
      rm -rf "$sukisu_dir"
      git clone -q --branch "$SUKISU_FORK_BRANCH" "$SUKISU_FORK_URL" "$sukisu_dir"
    fi
    ln -sfn ../KernelSU/kernel "$ksu_dir"

    # Known repo issue as of this script's writing: susfs-dev carries an
    # orphaned submodule gitlink for kernel-5.10/KernelSU-Next with no
    # matching .gitmodules entry on this branch (leftover from a merge with
    # main), which breaks `git submodule update --init --recursive` on a
    # clean clone. Strip it here so this script -- and anyone else cloning
    # susfs-dev fresh -- doesn't hit that.
    if git -C "$REPO" ls-files -s -- kernel-5.10/KernelSU-Next | grep -q '^160000'; then
      echo "[+] Removing orphaned KernelSU-Next submodule gitlink from susfs-dev..."
      git -C "$REPO" rm -q --cached kernel-5.10/KernelSU-Next
      echo "    [!] Staged removal -- review and commit this on susfs-dev."
    fi
  fi

  echo "[+] Verifying symbol consistency..."
  if "$VERIFY" "$REPO/kernel-5.10" "$ksu_dir"; then
    RESULTS+=("$branch: PASS")
  else
    RESULTS+=("$branch: FAIL")
  fi
}

process_branch "main"
process_branch "susfs-dev"

echo
echo "======================================================================"
echo " Summary"
echo "======================================================================"
FAILED=0
for r in "${RESULTS[@]}"; do
  echo "  $r"
  [[ "$r" == *FAIL* ]] && FAILED=1
done

if [ "$FAILED" -eq 1 ]; then
  echo
  echo "[!] At least one branch failed the symbol check. Do not trigger a"
  echo "    build until this is resolved -- review the missing-symbol"
  echo "    report above for each failing branch."
  exit 1
else
  echo
  echo "[+] Both branches pass the symbol check. Review the diffs staged by"
  echo "    this script (git status / git diff) on each branch, commit, then"
  echo "    it should be safe to trigger kernel_builder.yml."
fi
