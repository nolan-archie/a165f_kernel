#!/usr/bin/env bash
# apply_features.sh — run from the repo root (a165f_kernel/)
#
# Adds/enables, on BOTH `main` and `susfs-dev`:
#   - Baseband-guard (BBG) — vc-teahouse/Baseband-guard, via their official setup.sh
#   - CONFIG_TCP_CONGESTION_BBR / CONFIG_DEFAULT_TCP_CONG=bbr
#   - CONFIG_WIREGUARD (source already in-tree, just not built)
#   - CONFIG_IP_SET + common ipset match/target modules
#
# KPM is already enabled by the existing SukiSU-Ultra/KernelSU-Next baseline — nothing to add there.
#
# NOT done here on purpose:
#   - No touching of security/Kconfig LSM `default=` ordering. BBG upstream itself warns
#     that the sed-based auto-edit for that breaks `setup.sh --cleanup`. Do it by hand
#     if you want BBG enforcing by default; the script only wires the module in.
#   - No .config/menuconfig invocation — this only edits the defconfig source file.
#     You still need to build normally afterward.
#
# Review the diff on each branch before you build, and boot-test before you ship.

set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

KERNEL_DIR="kernel-5.10"
DEFCONFIG="custom_defconfigs/custom_defconfig"
BBG_SETUP_URL="https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh"
BRANCHES=(main susfs-dev)

add_config() {
  # add_config <file> <CONFIG_NAME> <value>
  local file="$1" name="$2" val="$3"
  if grep -qE "^${name}=" "$file"; then
    sed -i "s/^${name}=.*/${name}=${val}/" "$file"
  elif grep -qE "^# ${name} is not set" "$file"; then
    sed -i "s/^# ${name} is not set/${name}=${val}/" "$file"
  else
    echo "${name}=${val}" >> "$file"
  fi
}

apply_defconfig_flags() {
  echo "[*] Enabling BBR / WireGuard / IPSet in $DEFCONFIG"
  add_config "$DEFCONFIG" CONFIG_TCP_CONGESTION_BBR y
  add_config "$DEFCONFIG" CONFIG_DEFAULT_BBR y
  add_config "$DEFCONFIG" CONFIG_DEFAULT_TCP_CONG '"bbr"'
  add_config "$DEFCONFIG" CONFIG_WIREGUARD y
  add_config "$DEFCONFIG" CONFIG_IP_SET y
  add_config "$DEFCONFIG" CONFIG_IP_SET_MAX 256
  add_config "$DEFCONFIG" CONFIG_IP_SET_BITMAP_IP m
  add_config "$DEFCONFIG" CONFIG_IP_SET_HASH_IP m
  add_config "$DEFCONFIG" CONFIG_IP_SET_HASH_NET m
  add_config "$DEFCONFIG" CONFIG_NETFILTER_XT_SET m
}

apply_baseband_guard() {
  # BBG's own setup.sh is not idempotent (it blindly re-appends the obj-$(CONFIG_BBG)
  # line on every run). Skip entirely if it's already wired in on this branch.
  if grep -qE 'obj-\$\(CONFIG_BBG\)\s*\+=\s*baseband-guard/' "$KERNEL_DIR/security/Makefile" 2>/dev/null; then
    echo "[*] Baseband-guard already installed on this branch — skipping re-run."
    return 0
  fi

  # If a leftover Baseband-guard directory exists from a previous branch switch,
  # remove it so setup.sh's git clone doesn't fail.
  if [ -d "$KERNEL_DIR/Baseband-guard" ]; then
    echo "[*] Removing leftover Baseband-guard directory before install"
    rm -rf "$KERNEL_DIR/Baseband-guard"
  fi

  echo "[*] Fetching Baseband-guard setup.sh"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$BBG_SETUP_URL" -o "$tmp"
  chmod +x "$tmp"
  ( cd "$KERNEL_DIR" && bash "$tmp" )
  rm -f "$tmp"

  # setup.sh clones with its own .git, which git flags as a broken embedded repo.
  # Detach it so it's tracked as plain files, consistent with how KernelSU/SukiSU-Ultra
  # is already handled in this tree (plain clone, not a submodule).
  if [ -d "$KERNEL_DIR/Baseband-guard/.git" ]; then
    rm -rf "$KERNEL_DIR/Baseband-guard/.git"
    echo "[*] Detached nested .git in $KERNEL_DIR/Baseband-guard"
  fi

  echo "[!] BBG installed source-side. It printed defconfig/Kconfig instructions above —"
  echo "    read that output; it may list a CONFIG_LSM= line to add. This script does not"
  echo "    auto-apply it (see header notes) — add it to $DEFCONFIG by hand."
}

for BRANCH in "${BRANCHES[@]}"; do
  echo "=================================================================="
  echo "[*] Switching to branch: $BRANCH"
  git checkout "$BRANCH"
  git pull --ff-only || echo "[!] pull failed/skipped, continuing on local HEAD"

  # select-kernelsu.sh is not present on every branch; run only if it exists.
  if [ -x "./select-kernelsu.sh" ]; then
    ./select-kernelsu.sh
  else
    echo "[*] select-kernelsu.sh not present on $BRANCH — skipping"
  fi

  apply_baseband_guard
  apply_defconfig_flags

  if [ -n "$(git status --porcelain)" ]; then
    echo "[*] Diff for $BRANCH:"
    git --no-pager diff -- "$DEFCONFIG" "$KERNEL_DIR" | head -100
    echo "[*] Committing changes on '$BRANCH' (so the branch switch below doesn't get blocked)."
    git add -A
    git commit -m "Add BBG, enable BBR/WireGuard/IPSet"
    echo "[i] Review with: git show HEAD    (amend/reset if you don't like it)"
  else
    echo "[*] No changes on '$BRANCH' — already up to date."
  fi
done

echo "=================================================================="
echo "[*] Done. Review each branch's diff, then build + boot-test before flashing."
