#!/usr/bin/env bash
# scripts/build-main.sh
#
# Everything for the `main` branch in one file:
#   1. Update KernelSU-Next to pershoot/KernelSU-Next `dev-susfs`
#   2. Run your existing build.sh (unchanged)
#   3. Read the REAL .config/Makefile it produced
#   4. Send a Telegram build card (pass or fail)
#   5. Write GITHUB_OUTPUT values so the workflow can create the Release
#
# Usage: ./scripts/build-main.sh <repo-root>
# Requires env: BOT_TOKEN, CHAT_ID (Telegram). Optional: KERNEL_SRC_DIR, DOT_CONFIG_OVERRIDE

set -uo pipefail

REPO_ROOT="${1:?Usage: $0 <repo-root>}"
BRANCH="main"

# ---- CONFIG -----------------------------------------------------------------
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-$REPO_ROOT/kernel-5.10}"
KSU_DIR="$KERNEL_SRC_DIR/KernelSU-Next"
KSU_BRANCH="dev-susfs"
KSU_SOURCE_LABEL="KernelSU-Next"
DEVICE="A165F"
GITHUB_REPO="${GITHUB_REPOSITORY:-nolan-archie/a165f_kernel}"
# Snapshot these NOW — build.sh may reset/scrub the environment internally
_SAVED_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
_SAVED_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
if [ -z "$_SAVED_BOT_TOKEN" ] || [ -z "$_SAVED_CHAT_ID" ]; then
  echo "[telegram] WARNING: TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID empty at script start — check workflow secrets" >&2
fi
# -----------------------------------------------------------------------------

# ============================= Telegram helper ===============================
send_telegram_html() {
  local text="$1"
  if [ -z "$_SAVED_BOT_TOKEN" ] || [ -z "$_SAVED_CHAT_ID" ]; then
    echo "[telegram] BOT_TOKEN/CHAT_ID not set, skipping" >&2
    return 0
  fi
  curl -s -X POST "https://api.telegram.org/bot${_SAVED_BOT_TOKEN}/sendMessage" \
    -d chat_id="${_SAVED_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview="true" \
    --data-urlencode text="${text}" >/dev/null
}

build_info_block() {
  local out=""
  local kver="${KERNEL_FULL_VERSION:-unknown}"
  local ksu_ver="${KSU_VERSION_DISPLAY:-unknown}"
  local hook="${HOOK_TYPE:-unknown}"
  local susfs="${SUSFS_VERSION:-unknown}"
  local hash="${MANAGER_EXPECTED_HASH:-unknown}"
  local size="${MANAGER_EXPECTED_SIZE:-unknown}"

  if [ "$kver" != "unknown" ]; then
    kver="$(echo "$kver" | sed 's/Linux version //; s/ (.*//')"
  fi

  out="<b>Device:</b> $DEVICE
<b>Branch:</b> $BRANCH
<b>Kernel:</b> <code>$kver</code>"

  [ "$ksu_ver" != "unknown" ] && out="$out
<b>KSU Version:</b> <code>$ksu_ver</code>"
  [ "$hook" != "unknown" ] && out="$out
<b>Hook:</b> $hook"
  [ "$susfs" != "unknown" ] && out="$out
<b>SuSFS:</b> <code>$susfs</code>"
  [ "$hash" != "unknown" ] && out="$out
<b>Manager Hash:</b> <code>${hash:0:16}...</code>"
  [ "$size" != "unknown" ] && out="$out
<b>Manager Size:</b> <code>$size</code>"

  local enabled=""
  if [ -n "${FEATURES_BLOCK:-}" ] && [ "$FEATURES_BLOCK" != "(.config not found)" ] && [ "$FEATURES_BLOCK" != "(none enabled)" ]; then
    enabled="$(echo "$FEATURES_BLOCK" | grep '= true' | sed 's/ = true//' | tr '\n' ', ' | sed 's/, $//')"
  fi
  [ -n "$enabled" ] && out="$out

<b>Features:</b> <code>$enabled</code>"

  out="$out

<b>Built:</b> $(date -u '+%Y-%m-%d %H:%M UTC')"

  printf '%s' "$out"
}

send_build_card() {
  local status="$1" download_url="${2:-}"
  local header
  if [ "$status" = "success" ]; then
    header="Build Succeeded"
  else
    header="Build Failed"
  fi

  local body="<b>$header</b>

$(build_info_block)"

  if [ "$status" = "success" ] && [ -n "$download_url" ]; then
    body="$body

<a href=\"${download_url}\">Download Build</a>"
  fi
  if [ "$status" = "failure" ] && [ -n "${LOG_URL:-}" ]; then
    body="$body

<a href=\"${LOG_URL}\">View Logs</a>"
  fi

  send_telegram_html "$body"
}

# ============================ Step 1: update KSU ==============================
echo "[update] Ensuring KernelSU-Next is on branch: $KSU_BRANCH"
cd "$KERNEL_SRC_DIR"
PRE_SHA="none"
[ -d "KernelSU-Next/.git" ] && PRE_SHA="$(git -C KernelSU-Next rev-parse HEAD 2>/dev/null || echo none)"

if [ ! -d "KernelSU-Next/.git" ]; then
  echo "[update] Cloning fresh (branch: $KSU_BRANCH)..."
  git clone --branch "$KSU_BRANCH" "https://github.com/pershoot/KernelSU-Next.git" KernelSU-Next
else
  echo "[update] Fetching + forcing checkout of $KSU_BRANCH..."
  git -C KernelSU-Next fetch origin "$KSU_BRANCH"
  git -C KernelSU-Next checkout -B "$KSU_BRANCH" "origin/$KSU_BRANCH"
  git -C KernelSU-Next pull origin "$KSU_BRANCH"
fi

if [ ! -d "KernelSU-Next/.git" ]; then
  echo "[ERROR] KernelSU-Next missing after clone/checkout." >&2
  exit 1
fi

# Wire into tree
DRIVER_DIR=""
for d in "$KERNEL_SRC_DIR/common/drivers" "$KERNEL_SRC_DIR/aosp/drivers" "$KERNEL_SRC_DIR/drivers"; do
  [ -d "$d" ] && DRIVER_DIR="$d" && break
done
if [ -z "$DRIVER_DIR" ]; then
  echo "[ERROR] Could not find drivers/ under $KERNEL_SRC_DIR" >&2
  exit 1
fi

ln -sfn "$(realpath --relative-to="$DRIVER_DIR" "$KERNEL_SRC_DIR/KernelSU-Next/kernel")" "$DRIVER_DIR/kernelsu"
grep -q "kernelsu" "$DRIVER_DIR/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_DIR/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig" || \
  sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"
echo "[update] Symlink + Makefile + Kconfig wired."

POST_SHA="$(git -C KernelSU-Next rev-parse HEAD)"
CHANGED=0
[ "$PRE_SHA" != "$POST_SHA" ] && CHANGED=1
echo "[update] $PRE_SHA -> $POST_SHA (changed=$CHANGED)"
echo "CHANGED=$CHANGED" >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [ "$CHANGED" -eq 1 ]; then
  cd "$REPO_ROOT"
  git add -A
  git commit -m "Weekly sync: update ${KSU_SOURCE_LABEL} [skip ci]" || true
  git push origin HEAD:"$BRANCH" 2>/dev/null || true
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

# ============================ Step 3: verify =================================
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
  DESCRIBE="$(git -C "$KSU_DIR" describe --tags --always --dirty 2>/dev/null || true)"
  COUNT="$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || true)"
  SHORT_SHA="$(git -C "$KSU_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$DESCRIBE" ]; then
    KSU_VERSION_DISPLAY="$DESCRIBE"
  elif [ -n "$COUNT" ]; then
    KSU_VERSION_DISPLAY="r${COUNT} (${SHORT_SHA})"
  fi
fi

MANAGER_EXPECTED_HASH="unknown"
MANAGER_EXPECTED_SIZE="unknown"
if [ -f "$KSU_DIR/Makefile" ]; then
  HASH_MATCH="$(grep -hoE 'KSU_EXPECTED_HASH[[:space:]]*[:+]?=[[:space:]]*[a-fA-F0-9]+' "$KSU_DIR/Makefile" 2>/dev/null | head -n1 || true)"
  SIZE_MATCH="$(grep -hoE 'KSU_EXPECTED_SIZE[[:space:]]*[:+]?=[[:space:]]*(0x)?[0-9a-fA-F]+' "$KSU_DIR/Makefile" 2>/dev/null | head -n1 || true)"
  [ -n "$HASH_MATCH" ] && MANAGER_EXPECTED_HASH="$(echo "$HASH_MATCH" | sed -E 's/.*[=:][[:space:]]*//')"
  [ -n "$SIZE_MATCH" ] && MANAGER_EXPECTED_SIZE="$(echo "$SIZE_MATCH" | sed -E 's/.*[=:][[:space:]]*//')"
fi
if [ "$MANAGER_EXPECTED_HASH" = "unknown" ]; then
  HASH_MATCH="$(grep -rhoE 'EXPECTED_HASH[[:space:]]*[=:][[:space:]]*"?[a-fA-F0-9]+"?' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
  [ -n "$HASH_MATCH" ] && MANAGER_EXPECTED_HASH="$(echo "$HASH_MATCH" | sed -E 's/.*[=:][[:space:]]*//; s/"//g')"
fi
if [ "$MANAGER_EXPECTED_SIZE" = "unknown" ]; then
  SIZE_MATCH="$(grep -rhoE 'EXPECTED_SIZE[[:space:]]*[=:][[:space:]]*(0x)?[0-9a-fA-F]+' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
  [ -n "$SIZE_MATCH" ] && MANAGER_EXPECTED_SIZE="$(echo "$SIZE_MATCH" | sed -E 's/.*[=:][[:space:]]*//')"
fi

SUSFS_VERSION="unknown"
SUSFS_MATCH="$(grep -rhoE 'SUSFS_VERSION[[:space:]]+"[^"]+"' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
[ -z "$SUSFS_MATCH" ] && SUSFS_MATCH="$(grep -rhoE 'SUSFS_VERSION[[:space:]]+[vV][0-9.]+' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
[ -n "$SUSFS_MATCH" ] && SUSFS_VERSION="$(echo "$SUSFS_MATCH" | sed -E 's/.*"([^"]+)".*/\1/; s/.*[[:space:]]+([vV][0-9.]+).*/\1/')"

HOOK_TYPE="unknown"
if [ -f "$DOT_CONFIG" ]; then
  if grep -q '^CONFIG_KSU_MANUAL_HOOK=y' "$DOT_CONFIG"; then HOOK_TYPE="Manual"
  elif grep -q '^CONFIG_KPROBES=y' "$DOT_CONFIG"; then HOOK_TYPE="Kprobes"
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
    if grep -q "^${symbol}=y" "$DOT_CONFIG"; then
      FEATURES_BLOCK="${FEATURES_BLOCK}${label} = true
"
    fi
  done
  [ -z "$FEATURES_BLOCK" ] && FEATURES_BLOCK="(none enabled)"
else
  FEATURES_BLOCK="(.config not found)"
fi

KERNEL_FULL_VERSION="unknown"
IMAGE_PATH="$REPO_ROOT/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
if [ -f "$IMAGE_PATH" ]; then
  KERNEL_FULL_VERSION="$(zcat "$IMAGE_PATH" 2>/dev/null | strings | grep -m1 'Linux version' || echo unknown)"
fi

INFO_FILE="$REPO_ROOT/build-info.env"
{
  echo "## Build Info"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| **Device** | $DEVICE |"
  echo "| **Branch** | $BRANCH |"

  kver_short="${KERNEL_FULL_VERSION:-unknown}"
  [ "$kver_short" != "unknown" ] && kver_short="$(echo "$kver_short" | sed 's/Linux version //; s/ (.*//')"
  echo "| **Kernel** | $kver_short |"

  [ "${KSU_VERSION_DISPLAY:-unknown}" != "unknown" ] && echo "| **KSU Version** | $KSU_VERSION_DISPLAY |"
  [ "$HOOK_TYPE" != "unknown" ] && echo "| **Hook** | $HOOK_TYPE |"
  [ "$SUSFS_VERSION" != "unknown" ] && echo "| **SuSFS** | $SUSFS_VERSION |"
  [ "$MANAGER_EXPECTED_HASH" != "unknown" ] && echo "| **Manager Hash** | \`${MANAGER_EXPECTED_HASH:0:16}...\` |"
  [ "$MANAGER_EXPECTED_SIZE" != "unknown" ] && echo "| **Manager Size** | $MANAGER_EXPECTED_SIZE |"

  echo ""
  echo "### Enabled Features"
  echo ""
  if [ "$FEATURES_BLOCK" != "(.config not found)" ] && [ "$FEATURES_BLOCK" != "(none enabled)" ]; then
    echo "$(echo "$FEATURES_BLOCK" | grep '= true' | sed 's/ = true//' | sed 's/^/- /')"
  else
    echo "$FEATURES_BLOCK"
  fi
  echo ""
  echo "---"
  echo "Built: $(date -u '+%Y-%m-%d %H:%M UTC')"
} > "$INFO_FILE"

# ============================ Step 4: notify + outputs =========================
DIST_ZIP="$(find "$REPO_ROOT/dist" -maxdepth 1 -name '*-packaged.zip' 2>/dev/null | sort | tail -n1 || true)"

if [ "$BUILD_EXIT" -eq 0 ] && [ -n "$DIST_ZIP" ]; then
  echo "[build] SUCCESS — $DIST_ZIP"
  echo "status=success" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "artifact_path=$DIST_ZIP" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "run_tag=$RUN_TAG" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "info_file=$INFO_FILE" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  send_build_card "success" ""
else
  echo "[build] FAILED (exit $BUILD_EXIT, artifact: ${DIST_ZIP:-none})"
  echo "status=failure" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  LOG_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPO}/actions/runs/${GITHUB_RUN_ID:-}"
  send_build_card "failure" ""
  exit 1
fi
