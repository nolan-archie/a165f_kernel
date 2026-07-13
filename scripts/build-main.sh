#!/usr/bin/env bash
# scripts/build-main.sh
#
# Everything for the `main` branch in one file:
#   1. Update KernelSU-Next to pershoot/KernelSU-Next `dev-susfs`
#   2. Run your existing build.sh (unchanged)
#   3. Read the REAL .config/Makefile it produced — no hardcoded feature claims
#   4. Send a Telegram build card (pass or fail)
#   5. Write GITHUB_OUTPUT values so the workflow can create the Release
#
# Usage: ./scripts/build-main.sh <repo-root>
# Requires env: BOT_TOKEN, CHAT_ID (Telegram). Optional: KERNEL_SRC_DIR, DOT_CONFIG_OVERRIDE

set -uo pipefail   # not -e: a failed build must still reach the notify step

REPO_ROOT="${1:?Usage: $0 <repo-root>}"
BRANCH="main"

# ---- CONFIG: confirm once against your actual tree -------------------------
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-$REPO_ROOT/kernel-5.10}"
KSU_DIR="$KERNEL_SRC_DIR/KernelSU-Next"
KSU_BRANCH="dev-susfs"
KSU_SETUP_URL="https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/${KSU_BRANCH}/kernel/setup.sh"
KSU_SOURCE_LABEL="KernelSU-Next (pershoot/${KSU_BRANCH})"
DEVICE="A165F"
GITHUB_REPO="${GITHUB_REPOSITORY:-nolan-archie/a165f_kernel}"
# ------------------------------------------------------------------------------

# ============================= Telegram helper ===============================
send_telegram_html() {
  local text="$1"
  if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ]; then
    echo "[telegram] BOT_TOKEN/CHAT_ID not set, skipping" >&2
    return 0
  fi
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview="true" \
    --data-urlencode text="${text}" >/dev/null
}

send_build_card() {
  local status="$1" download_url="${2:-}"
  local header
  [ "$status" = "success" ] && header="Kernel Build Succeeded" || header="Kernel Build Failed"

  local body
  body=$(printf '<b>%s</b>\n\n<pre>Repo: %s\nBranch: %s\nDevice: %s\nKernel version: %s\nKSU source: %s\nKSU version: %s\nManager hook: %s\nSuSFS version: %s\nManager EXPECTED_HASH: %s\nManager EXPECTED_SIZE: %s\nBuild date: %s</pre>' \
    "$header" "$GITHUB_REPO" "$BRANCH" "$DEVICE" \
    "${KERNEL_FULL_VERSION:-unknown}" "$KSU_SOURCE_LABEL" "${KSU_VERSION_DISPLAY:-unknown}" \
    "${HOOK_TYPE:-unknown}" "${SUSFS_VERSION:-unknown}" \
    "${MANAGER_EXPECTED_HASH:-unknown}" "${MANAGER_EXPECTED_SIZE:-unknown}" \
    "$(date -u '+%Y-%m-%d %H:%M UTC')")

  if [ -n "${FEATURES_BLOCK:-}" ]; then
    body="${body}
<pre>${FEATURES_BLOCK}</pre>"
  fi

  if [ "$status" = "success" ] && [ -n "$download_url" ]; then
    body="${body}

<a href=\"${download_url}\">Download build</a>"
  fi
  if [ "$status" = "failure" ] && [ -n "${LOG_URL:-}" ]; then
    body="${body}

<a href=\"${LOG_URL}\">View build log</a>"
  fi

  send_telegram_html "$body"
}

# ============================ Step 1: update KSU ==============================
echo "[update] Running upstream setup.sh for branch: $KSU_BRANCH"
cd "$KERNEL_SRC_DIR"
PRE_SHA="none"
[ -d "KernelSU-Next/.git" ] && PRE_SHA="$(git -C KernelSU-Next rev-parse HEAD 2>/dev/null || echo none)"

curl -LSs "$KSU_SETUP_URL" | bash -s "$KSU_BRANCH"

if [ ! -d "KernelSU-Next/.git" ]; then
  echo "[ERROR] KernelSU-Next missing after setup.sh — setup failed." >&2
  exit 1
fi
POST_SHA="$(git -C KernelSU-Next rev-parse HEAD)"
CHANGED=0
[ "$PRE_SHA" != "$POST_SHA" ] && CHANGED=1
echo "[update] $PRE_SHA -> $POST_SHA (changed=$CHANGED)"
echo "CHANGED=$CHANGED" >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [ "$CHANGED" -eq 1 ]; then
  cd "$REPO_ROOT"
  git add -A
  git commit -m "Weekly sync: update ${KSU_SOURCE_LABEL} [skip ci]" || true
  git push origin HEAD:"$BRANCH" || echo "[update] push skipped/failed (non-fatal)" >&2
fi

# ============================ Step 2: build ====================================
cd "$REPO_ROOT"
RUN_TAG="$(date -u '+%Y%m%d')-${BRANCH}-$(git rev-parse --short HEAD)"
export BUILD_KERNEL_VERSION="$RUN_TAG"
echo "[build] BUILD_KERNEL_VERSION=$BUILD_KERNEL_VERSION"

set +e
./build.sh
BUILD_EXIT=$?
set -e

# ============================ Step 3: verify (read reality, don't assume) =====
DOT_CONFIG="${DOT_CONFIG_OVERRIDE:-}"
if [ -z "$DOT_CONFIG" ]; then
  for candidate in \
    "$REPO_ROOT/out/target/product/a16/obj/KERNEL_OBJ/.config" \
    "$REPO_ROOT/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/.config"
  do
    [ -f "$candidate" ] && { DOT_CONFIG="$candidate"; break; }
  done
  [ -z "$DOT_CONFIG" ] && DOT_CONFIG="$(find "$REPO_ROOT/out" -maxdepth 6 -name ".config" 2>/dev/null | head -n1 || true)"
fi
echo "[verify] Using .config: ${DOT_CONFIG:-none found}"

KSU_VERSION_DISPLAY="unknown"
if git -C "$KSU_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  DESCRIBE="$(git -C "$KSU_DIR" describe --tags --always --dirty 2>/dev/null || echo "")"
  COUNT="$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo "")"
  SHORT_SHA="$(git -C "$KSU_DIR" rev-parse --short HEAD 2>/dev/null || echo "")"
  if [ -n "$DESCRIBE" ]; then KSU_VERSION_DISPLAY="$DESCRIBE"
  elif [ -n "$COUNT" ]; then KSU_VERSION_DISPLAY="commit-count:${COUNT} (${SHORT_SHA})"; fi
fi

MANAGER_EXPECTED_HASH="unknown"; MANAGER_EXPECTED_SIZE="unknown"
HASH_MATCH="$(grep -rhoE 'KSU_EXPECTED_HASH[[:space:]]*:?=[[:space:]]*[A-Za-z0-9]+' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
SIZE_MATCH="$(grep -rhoE 'KSU_EXPECTED_SIZE[[:space:]]*:?=[[:space:]]*[A-Za-z0-9x]+' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
[ -n "$HASH_MATCH" ] && MANAGER_EXPECTED_HASH="${HASH_MATCH##*[:=] }"
[ -n "$SIZE_MATCH" ] && MANAGER_EXPECTED_SIZE="${SIZE_MATCH##*[:=] }"

SUSFS_VERSION="unknown"
SUSFS_MATCH="$(grep -rhoE 'SUSFS_VERSION[[:space:]]+"[^"]+"' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
[ -n "$SUSFS_MATCH" ] && SUSFS_VERSION="$(echo "$SUSFS_MATCH" | sed -E 's/.*"([^"]+)"/\1/')"

HOOK_TYPE="unknown"
if [ -f "$DOT_CONFIG" ]; then
  if grep -q '^CONFIG_KSU_MANUAL_HOOK=y' "$DOT_CONFIG"; then HOOK_TYPE="Manual syscall hook"
  elif grep -q '^CONFIG_KPROBES=y' "$DOT_CONFIG"; then HOOK_TYPE="Kprobes hook"
  elif grep -q '^CONFIG_MODULES=y' "$DOT_CONFIG"; then HOOK_TYPE="LKM"
  fi
fi

declare -A FEATURE_CHECKS=(
  ["SuSFS"]="CONFIG_KSU_SUSFS"
  ["Manual Hooks"]="CONFIG_KSU_MANUAL_HOOK"
  ["KPM"]="CONFIG_KPM"
  ["Magic Mount"]="CONFIG_KSU_SUSFS_SUS_MOUNT"
  ["LZ4K"]="CONFIG_LZ4K"
  ["LZ4KD"]="CONFIG_LZ4KD"
  ["BBR"]="CONFIG_TCP_CONG_BBR"
)
FEATURES_BLOCK=""
if [ -f "$DOT_CONFIG" ]; then
  for label in "${!FEATURE_CHECKS[@]}"; do
    symbol="${FEATURE_CHECKS[$label]}"
    if grep -q "^${symbol}=y" "$DOT_CONFIG"; then val="true"
    elif grep -q "^# ${symbol} is not set" "$DOT_CONFIG"; then val="false"
    else val="unknown"; fi
    FEATURES_BLOCK="${FEATURES_BLOCK}${label} = ${val}
"
  done
else
  FEATURES_BLOCK="(.config not found — features unverifiable)"
fi

KERNEL_FULL_VERSION="unknown"
IMAGE_PATH="$REPO_ROOT/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
[ -f "$IMAGE_PATH" ] && KERNEL_FULL_VERSION="$(zcat "$IMAGE_PATH" 2>/dev/null | strings | grep -m1 'Linux version' || echo unknown)"

# Write a plain-text info block for the GitHub Release body
INFO_FILE="$REPO_ROOT/build-info.env"
{
  echo "Repo: $GITHUB_REPO"
  echo "Branch: $BRANCH"
  echo "Device: $DEVICE"
  echo "Kernel version: $KERNEL_FULL_VERSION"
  echo "KSU source: $KSU_SOURCE_LABEL"
  echo "KSU version: $KSU_VERSION_DISPLAY"
  echo "Manager hook: $HOOK_TYPE"
  echo "SuSFS version: $SUSFS_VERSION"
  echo "Manager EXPECTED_HASH: $MANAGER_EXPECTED_HASH"
  echo "Manager EXPECTED_SIZE: $MANAGER_EXPECTED_SIZE"
  echo ""
  echo "Features:"
  echo "$FEATURES_BLOCK"
} > "$INFO_FILE"

# ============================ Step 4: notify + outputs =========================
DIST_ZIP="$(find "$REPO_ROOT/dist" -maxdepth 1 -name '*-packaged.zip' 2>/dev/null | sort | tail -n1 || true)"

if [ "$BUILD_EXIT" -eq 0 ] && [ -n "$DIST_ZIP" ]; then
  echo "[build] SUCCESS — $DIST_ZIP"
  echo "status=success" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "artifact_path=$DIST_ZIP" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "run_tag=$RUN_TAG" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "info_file=$INFO_FILE" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  send_build_card "success" ""   # release link comes in a follow-up ping (workflow step 2)
else
  echo "[build] FAILED (exit $BUILD_EXIT, artifact: ${DIST_ZIP:-none})"
  echo "status=failure" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  LOG_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPO}/actions/runs/${GITHUB_RUN_ID:-}"
  send_build_card "failure" ""
  exit 1
fi
