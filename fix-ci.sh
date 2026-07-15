#!/usr/bin/env bash
# fix-ci.sh - resolves the a165f_kernel build/telegram/packaging issues on
# both main and susfs-dev branches, then commits + pushes each branch.
#
# Run this from the ROOT of your local a165f_kernel clone.
set -euo pipefail

if [ ! -d .git ]; then echo "Run this from the kernel repo root (git repo)."; exit 1; fi
ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin main susfs-dev

write_shared_files() {
  mkdir -p scripts
  cat > scripts/lib-telegram.sh <<'TELEGRAM_LIB_EOF'
#!/usr/bin/env bash
# scripts/lib-telegram.sh
#
# Single shared Telegram notifier for build-main.sh and build-susfs-dev.sh.
# Fixes the previous env-var mismatch: the workflow always exports BOT_TOKEN
# and CHAT_ID (see .github/workflows/kernel_builder.yml), so that is what we
# read here — never TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID.
#
# Expects these to already be exported by the caller before build_card is used:
#   BRANCH, DEVICE, KSU_SOURCE_LABEL, KERNEL_FULL_VERSION, KSU_VERSION_DISPLAY,
#   HOOK_TYPE, SUSFS_VERSION, MANAGER_EXPECTED_HASH, MANAGER_EXPECTED_SIZE,
#   FEATURES_BLOCK, GITHUB_REPO, LOG_URL (on failure)

_TG_BOT_TOKEN="${BOT_TOKEN:-}"
_TG_CHAT_ID="${CHAT_ID:-}"

if [ -z "$_TG_BOT_TOKEN" ] || [ -z "$_TG_CHAT_ID" ]; then
  echo "[telegram] WARNING: BOT_TOKEN/CHAT_ID empty at script start — check workflow secrets" >&2
fi

telegram_send() {
  local text="$1"
  if [ -z "$_TG_BOT_TOKEN" ] || [ -z "$_TG_CHAT_ID" ]; then
    echo "[telegram] BOT_TOKEN/CHAT_ID not set, skipping" >&2
    return 0
  fi
  local resp
  resp="$(curl -s -X POST "https://api.telegram.org/bot${_TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${_TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview="true" \
    --data-urlencode text="${text}")"
  if command -v grep >/dev/null 2>&1 && ! echo "$resp" | grep -q '"ok":true'; then
    echo "[telegram] send failed: $resp" >&2
    return 1
  fi
  echo "[telegram] message sent"
}

_tg_short_kver() {
  local kver="${KERNEL_FULL_VERSION:-unknown}"
  [ "$kver" != "unknown" ] && kver="$(echo "$kver" | sed 's/Linux version //; s/ (.*//')"
  printf '%s' "$kver"
}

_tg_feature_lines() {
  # FEATURES_BLOCK is "Label = true/false/unknown\n" per line.
  # Only show enabled + explicitly-disabled, skip "unknown" (usually
  # means the symbol wasn't found because .config is missing).
  local block="${FEATURES_BLOCK:-}"
  [ -z "$block" ] && { echo "(none enabled)"; return; }
  local line label val out=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    label="${line%% = *}"
    val="${line##* = }"
    case "$val" in
      true)  out="${out}✅ ${label}
" ;;
      false) out="${out}⬜ ${label}
" ;;
    esac
  done <<< "$block"
  [ -z "$out" ] && out="(none enabled)"
  printf '%s' "$out"
}

# send_build_card <status: success|failure> [download_url]
send_build_card() {
  local status="$1" download_url="${2:-}"
  local emoji header
  if [ "$status" = "success" ]; then
    emoji="✅"; header="Build Succeeded"
  else
    emoji="❌"; header="Build Failed"
  fi

  local body
  body="<b>${emoji} ${header}</b>
<b>Repo:</b> ${GITHUB_REPO:-unknown}
<b>Branch:</b> <code>${BRANCH:-unknown}</code>
<b>Device:</b> ${DEVICE:-unknown}
<b>Kernel:</b> <code>$(_tg_short_kver)</code>
<b>KSU source:</b> ${KSU_SOURCE_LABEL:-unknown}
<b>KSU version:</b> <code>${KSU_VERSION_DISPLAY:-unknown}</code>
<b>Hook:</b> ${HOOK_TYPE:-unknown}
<b>SuSFS:</b> <code>${SUSFS_VERSION:-unknown}</code>"

  if [ -n "${MANAGER_EXPECTED_HASH:-}" ] && [ "${MANAGER_EXPECTED_HASH}" != "unknown" ]; then
    body="${body}
<b>Manager hash:</b> <code>${MANAGER_EXPECTED_HASH:0:16}...</code>"
  fi
  if [ -n "${MANAGER_EXPECTED_SIZE:-}" ] && [ "${MANAGER_EXPECTED_SIZE}" != "unknown" ]; then
    body="${body}
<b>Manager size:</b> ${MANAGER_EXPECTED_SIZE}"
  fi

  body="${body}

<b>Features:</b>
$(_tg_feature_lines)
<b>Built:</b> $(date -u '+%Y-%m-%d %H:%M UTC')"

  if [ "$status" = "success" ] && [ -n "$download_url" ]; then
    body="${body}

<a href=\"${download_url}\">Download build</a>"
  fi
  if [ "$status" = "failure" ] && [ -n "${LOG_URL:-}" ]; then
    body="${body}

<a href=\"${LOG_URL}\">View build log</a>"
  fi

  telegram_send "$body"
}
TELEGRAM_LIB_EOF
  chmod +x scripts/lib-telegram.sh
  rm -f scripts/automate_updates.sh
}

write_build_main() {
  cat > scripts/build-main.sh <<'BUILD_MAIN_EOF'
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
# Telegram creds come from BOT_TOKEN/CHAT_ID (set by kernel_builder.yml)
# and are read directly by scripts/lib-telegram.sh — sourced below.
# -----------------------------------------------------------------------------

# Shared Telegram helpers (send_telegram_html / send_build_card)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-telegram.sh"

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
export PACKAGE_PREFIX="KernelSU-NEXT"
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
BUILD_MAIN_EOF
  chmod +x scripts/build-main.sh
}

write_build_susfs() {
  cat > scripts/build-susfs-dev.sh <<'BUILD_SUSFS_EOF'
#!/usr/bin/env bash
# scripts/build-susfs-dev.sh
#
# Everything for the `susfs-dev` branch in one file:
#   1. Update manager-detection code via YOUR existing sync-manager-detection.sh
#   2. Run your existing build.sh (unchanged)
#   3. Read the REAL .config/Makefile it produced
#   4. Send a Telegram build card (pass or fail)
#   5. Write GITHUB_OUTPUT values so the workflow can create the Release
#
# Usage: ./scripts/build-susfs-dev.sh <repo-root>
# Requires env: BOT_TOKEN, CHAT_ID (Telegram). Optional: KERNEL_SRC_DIR, KSU_DIR, DOT_CONFIG_OVERRIDE

set -uo pipefail

REPO_ROOT="${1:?Usage: $0 <repo-root>}"
BRANCH="susfs-dev"

# ---- CONFIG -----------------------------------------------------------------
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-$REPO_ROOT/kernel-5.10}"
KSU_DIR="${KSU_DIR:-$KERNEL_SRC_DIR/drivers/kernelsu}"
SYNC_SCRIPT="$REPO_ROOT/sync-manager-detection.sh"
KSU_SOURCE_LABEL="SukiSU-Ultra"
DEVICE="A165F"
GITHUB_REPO="${GITHUB_REPOSITORY:-nolan-archie/a165f_kernel}"
# Telegram creds come from BOT_TOKEN/CHAT_ID (set by kernel_builder.yml)
# and are read directly by scripts/lib-telegram.sh — sourced below.
# -----------------------------------------------------------------------------

echo "[update] Ensuring git submodules are initialized..."
git -C "$REPO_ROOT" submodule update --init --recursive 2>/dev/null || true

# Symlink handling (same as before)
if [ ! -e "$KSU_DIR" ]; then
  echo "[update] KSU_DIR missing, resolving real source..."
  CANDIDATE=""
  [ -d "$KERNEL_SRC_DIR/KernelSU/kernel" ] && CANDIDATE="$KERNEL_SRC_DIR/KernelSU/kernel"
  [ -z "$CANDIDATE" ] && [ -d "$KERNEL_SRC_DIR/KernelSU" ] && CANDIDATE="$KERNEL_SRC_DIR/KernelSU"
  if [ -z "$CANDIDATE" ]; then
    CANDIDATE="$(find "$KERNEL_SRC_DIR" -maxdepth 3 -type d -iname "kernel" \
      \( -ipath "*sukisu*" -o -ipath "*kernelsu*" \) 2>/dev/null | head -n1)"
  fi
  if [ -n "$CANDIDATE" ]; then
    [ ! -f "$CANDIDATE/Makefile" ] && CANDIDATE="$(dirname "$(find "$CANDIDATE" -maxdepth 3 -type f -iname "Makefile" 2>/dev/null | head -n1)")"
    ln -sfn "$(realpath --relative-to="$KERNEL_SRC_DIR/drivers" "$CANDIDATE")" "$KERNEL_SRC_DIR/drivers/kernelsu"
    echo "[update] Symlinked drivers/kernelsu -> $CANDIDATE"
  fi
fi

# Shared Telegram helpers (send_telegram_html / send_build_card)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-telegram.sh"

# ============================ Step 1: sync manager files =======================
if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "[ERROR] sync-manager-detection.sh not found at $SYNC_SCRIPT" >&2
  exit 1
fi
if [ ! -d "$KSU_DIR" ]; then
  echo "[ERROR] KSU_DIR '$KSU_DIR' does not exist." >&2
  exit 1
fi

echo "[update] Snapshotting manager files..."
BEFORE_HASH="$(find "$KSU_DIR/manager" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum || echo none)"

echo "[update] Running sync-manager-detection.sh..."
bash "$SYNC_SCRIPT" "$KSU_DIR"

AFTER_HASH="$(find "$KSU_DIR/manager" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum || echo none)"
CHANGED=0
[ "$BEFORE_HASH" != "$AFTER_HASH" ] && CHANGED=1
echo "[update] changed=$CHANGED"
echo "CHANGED=$CHANGED" >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [ "$CHANGED" -eq 1 ]; then
  cd "$REPO_ROOT"
  git add -A
  git commit -m "Weekly sync: update manager-detection [skip ci]" || true
  git push origin HEAD:"$BRANCH" 2>/dev/null || true
fi

# ============================ Step 2: build ====================================
cd "$REPO_ROOT"
RUN_TAG="$(date -u '+%Y%m%d')-${BRANCH}-$(git rev-parse --short HEAD)"
export BUILD_KERNEL_VERSION="$RUN_TAG"
export PACKAGE_PREFIX="SukiSU-Ultra"
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

# KSU version
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
else
  KSU_VERSION_DISPLAY="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
fi

# EXPECTED_HASH / EXPECTED_SIZE — robust parsing
MANAGER_EXPECTED_HASH="unknown"
MANAGER_EXPECTED_SIZE="unknown"
if [ -f "$KSU_DIR/Makefile" ]; then
  # Try multiple patterns: :=, =, ?=, +=
  HASH_MATCH="$(grep -hoE 'KSU_EXPECTED_HASH[[:space:]]*[:+]?=[[:space:]]*[a-fA-F0-9]+' "$KSU_DIR/Makefile" 2>/dev/null | head -n1 || true)"
  SIZE_MATCH="$(grep -hoE 'KSU_EXPECTED_SIZE[[:space:]]*[:+]?=[[:space:]]*(0x)?[0-9a-fA-F]+' "$KSU_DIR/Makefile" 2>/dev/null | head -n1 || true)"
  [ -n "$HASH_MATCH" ] && MANAGER_EXPECTED_HASH="$(echo "$HASH_MATCH" | sed -E 's/.*[=:][[:space:]]*//')"
  [ -n "$SIZE_MATCH" ] && MANAGER_EXPECTED_SIZE="$(echo "$SIZE_MATCH" | sed -E 's/.*[=:][[:space:]]*//')"
fi

# Also check in manager/ subdir if not found in Makefile
if [ "$MANAGER_EXPECTED_HASH" = "unknown" ]; then
  HASH_MATCH="$(grep -rhoE 'EXPECTED_HASH[[:space:]]*[=:][[:space:]]*"?[a-fA-F0-9]+"?' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
  [ -n "$HASH_MATCH" ] && MANAGER_EXPECTED_HASH="$(echo "$HASH_MATCH" | sed -E 's/.*[=:][[:space:]]*//; s/"//g')"
fi
if [ "$MANAGER_EXPECTED_SIZE" = "unknown" ]; then
  SIZE_MATCH="$(grep -rhoE 'EXPECTED_SIZE[[:space:]]*[=:][[:space:]]*(0x)?[0-9a-fA-F]+' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
  [ -n "$SIZE_MATCH" ] && MANAGER_EXPECTED_SIZE="$(echo "$SIZE_MATCH" | sed -E 's/.*[=:][[:space:]]*//')"
fi

# SuSFS version — handle #define and string variations
SUSFS_VERSION="unknown"
SUSFS_MATCH="$(grep -rhoE 'SUSFS_VERSION[[:space:]]+"[^"]+"' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
[ -z "$SUSFS_MATCH" ] && SUSFS_MATCH="$(grep -rhoE 'SUSFS_VERSION[[:space:]]+[vV][0-9.]+' "$KSU_DIR" 2>/dev/null | head -n1 || true)"
[ -n "$SUSFS_MATCH" ] && SUSFS_VERSION="$(echo "$SUSFS_MATCH" | sed -E 's/.*"([^"]+)".*/\1/; s/.*[[:space:]]+([vV][0-9.]+).*/\1/')"

# Hook type
HOOK_TYPE="unknown"
if [ -f "$DOT_CONFIG" ]; then
  if grep -q '^CONFIG_KSU_MANUAL_HOOK=y' "$DOT_CONFIG"; then HOOK_TYPE="Manual"
  elif grep -q '^CONFIG_KPROBES=y' "$DOT_CONFIG"; then HOOK_TYPE="Kprobes"
  elif grep -q '^CONFIG_MODULES=y' "$DOT_CONFIG"; then HOOK_TYPE="LKM"
  fi
fi

# Features — compact, only show enabled
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

# Kernel version
KERNEL_FULL_VERSION="unknown"
IMAGE_PATH="$REPO_ROOT/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"
if [ -f "$IMAGE_PATH" ]; then
  KERNEL_FULL_VERSION="$(zcat "$IMAGE_PATH" 2>/dev/null | strings | grep -m1 'Linux version' || echo unknown)"
fi

# Write clean info file for GitHub Release
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
BUILD_SUSFS_EOF
  chmod +x scripts/build-susfs-dev.sh
}

write_fixed_buildsh() {
  cat > build.sh <<'BUILD_SH_EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIREMENTS_FILE="${SCRIPT_DIR}/.requirements"
TOOLCHAIN_MARKER="${SCRIPT_DIR}/.toolchain_installed"
TOOLCHAIN_URL="https://github.com/ravindu644/android_kernel_a165f/releases/download/toolchain/toolchain.tar.gz"
TOOLCHAIN_ARCHIVE="toolchain.tar.gz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() { log_error "$*"; exit 1; }

check_command() { command -v "$1" >/dev/null 2>&1; }

detect_package_manager() {
    if check_command pacman; then
        echo "pacman"
    elif check_command apt; then
        echo "apt"
    elif check_command dnf; then
        echo "dnf"
    elif check_command zypper; then
        echo "zypper"
    else
        die "Unsupported package manager"
    fi
}

install_dependencies() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    log_info "Package manager: ${pkg_manager}"

    case "${pkg_manager}" in
        pacman)
            sudo pacman -S --needed --noconfirm \
                base-devel rsync python git tar gzip curl wget bc cpio flex bison zip unzip openssl dtc \
                || die "Dependency install failed"
            ;;
        apt)
            sudo apt update || die "Package update failed"
            sudo apt install -y \
                build-essential rsync python3 python3-dev git tar gzip curl wget bc cpio flex bison zip unzip \
                libncurses-dev libssl-dev device-tree-compiler \
                || die "Dependency install failed"
            ;;
        dnf)
            sudo dnf install -y \
                gcc gcc-c++ make rsync python3 git tar gzip curl wget bc cpio flex bison zip unzip openssl-devel dtc \
                || die "Dependency install failed"
            ;;
        *)
            die "Package manager not supported: ${pkg_manager}"
            ;;
    esac

    log_success "Dependencies installed"
}

check_and_install_requirements() {
    if [[ -f "${REQUIREMENTS_FILE}" ]]; then
        log_info "Requirements already satisfied"
        return 0
    fi

    install_dependencies
    touch "${REQUIREMENTS_FILE}" 2>/dev/null || true
    log_success "Requirements satisfied"
}

download_toolchain() {
    local temp_dir
    temp_dir=$(mktemp -d) || die "Cannot create temp directory"
    trap 'rm -rf "${temp_dir:-}"' EXIT

    log_info "Downloading toolchain"
    curl -L --progress-bar -o "${temp_dir}/${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}" \
        || die "Toolchain download failed"

    log_info "Extracting toolchain"
    tar -xzf "${temp_dir}/${TOOLCHAIN_ARCHIVE}" -C "${SCRIPT_DIR}" \
        || die "Toolchain extraction failed"

    log_success "Toolchain extracted"
}

setup_toolchain() {
    if [[ -f "${TOOLCHAIN_MARKER}" ]] && [[ -d "${SCRIPT_DIR}/kernel/prebuilts" ]] && [[ -d "${SCRIPT_DIR}/prebuilts" ]]; then
        log_info "Toolchain already installed"
        return 0
    fi

    download_toolchain

    if [[ ! -d "${SCRIPT_DIR}/kernel/prebuilts" || ! -d "${SCRIPT_DIR}/prebuilts" ]]; then
        die "Toolchain directories missing after extraction"
    fi

    touch "${TOOLCHAIN_MARKER}" 2>/dev/null || true
    log_success "Toolchain installed"
}

fix_gen_build_config() {
    local py="${SCRIPT_DIR}/kernel-5.10/scripts/gen_build_config.py"

    if [[ ! -f "$py" ]]; then
        log_warn "gen_build_config.py not found, skipping fix"
        return 0
    fi

    if grep -q '^print(' "$py" 2>/dev/null && ! grep -q '^print ' "$py" 2>/dev/null; then
        log_info "gen_build_config.py already fixed, skipping"
        return 0
    fi

    log_info "Fixing gen_build_config.py for Python 3"
    python3 - "$py" <<'PYEOF'
import sys

py = sys.argv[1]
with open(py, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    stripped = line.lstrip()
    if stripped.startswith('print ') and not stripped.startswith('print('):
        new_line = line.replace('print ', 'print(', 1)
        if new_line.endswith('\n'):
            new_line = new_line[:-1] + ')' + '\n'
        else:
            new_line = new_line + ')'
        new_lines.append(new_line)
    else:
        new_lines.append(line)

with open(py, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
PYEOF

    if python3 -m py_compile "$py"; then
        log_success "gen_build_config.py syntax OK"
    else
        log_warn "Syntax check failed"
    fi
}

generate_build_config() {
    log_info "Generating build config"

    mkdir -p "${SCRIPT_DIR}/kernel-5.10/arch/arm64/configs"
    cd "${SCRIPT_DIR}/kernel-5.10/arch/arm64/configs" || die "Cannot access configs"

    {
        cat a16_00_defconfig
        [[ -f entry_level.config ]] && cat entry_level.config
        cat "${SCRIPT_DIR}/custom_defconfigs/custom_defconfig"
        printf 'CONFIG_LOCALVERSION_AUTO=n\nCONFIG_LOCALVERSION="-nolanarchie-dev"\n'
    } > a16_00_custom_defconfig

    log_info "Merged defconfig lines: $(wc -l < a16_00_custom_defconfig)"

    local abs_out_dir="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ"
    mkdir -p "${abs_out_dir}"
    rm -f "${abs_out_dir}/build.config" \
          "${abs_out_dir}/build.config.gki.aarch64" \
          "${abs_out_dir}/build.config.mtk"

    cd "${SCRIPT_DIR}/kernel-5.10" || die "Cannot access kernel-5.10"

    python3 scripts/gen_build_config.py \
        --kernel-defconfig a16_00_custom_defconfig \
        -m user \
        -o "${abs_out_dir}/build.config" \
        || die "Build config generation failed"

    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"
    log_success "Build config generated"
}

create_symlinks() {
    log_info "Creating root symlinks"
    for d in custom_defconfigs prebuilts_helio_g99 oem_prebuilt_images; do
        if [[ -d "${SCRIPT_DIR}/${d}" ]] && [[ ! -e "/${d}" ]]; then
            if sudo ln -sf "${SCRIPT_DIR}/${d}" "/${d}" 2>/dev/null; then
                log_success "Symlink created: /${d}"
            else
                log_warn "Symlink failed for /${d}, continuing"
            fi
        elif [[ -e "/${d}" ]]; then
            log_info "Symlink exists: /${d}"
        fi
    done
}

setup_environment() {
    export BUILD_KERNEL_VERSION="${BUILD_KERNEL_VERSION:-dev}"
    log_info "Kernel version: ${BUILD_KERNEL_VERSION}"

    export ARCH=arm64
    export PLATFORM_VERSION=13
    export TARGET_BUILD_VARIANT=user
    export CROSS_COMPILE="aarch64-linux-gnu-"
    export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"

    # These must be relative to kernel/ because build.sh runs from there
    export OUT_DIR="../out/target/product/a16/obj/KERNEL_OBJ"
    export DIST_DIR="../out/target/product/a16/obj/KERNEL_OBJ"
    export BUILD_CONFIG="../out/target/product/a16/obj/KERNEL_OBJ/build.config"

    export MERGE_CONFIG="${SCRIPT_DIR}/kernel-5.10/scripts/kconfig/merge_config.sh"

    export GKI_RAMDISK_PREBUILT_BINARY="${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4"
    export MKBOOTIMG_EXTRA_ARGS="--os_version 12.0.0 --os_patch_level 2025-05-00 --pagesize 4096"

    export SKIP_MRPROPER=1
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export ABI_DEFINITION=
    export BUILD_BOOT_IMG=1
    export MKBOOTIMG_PATH="${SCRIPT_DIR}/mkbootimg/mkbootimg.py"
    export KERNEL_BINARY=Image.gz
    export BOOT_IMAGE_HEADER_VERSION=4
    export SKIP_VENDOR_BOOT=1
    export AVB_SIGN_BOOT_IMG=1
    export AVB_BOOT_PARTITION_SIZE=67108864
    export AVB_BOOT_KEY="${SCRIPT_DIR}/mkbootimg/tests/data/testkey_rsa2048.pem"
    export AVB_BOOT_ALGORITHM=SHA256_RSA2048
    export AVB_BOOT_PARTITION_NAME=boot
    export LTO=thin
    export KCFLAGS="-Wframe-larger-than=16384"

    export WDIR="${SCRIPT_DIR}"

    log_success "Environment configured"
}

verify_prerequisites() {
    local missing=()
    [[ ! -d "${SCRIPT_DIR}/kernel-5.10" ]] && missing+=("kernel-5.10")
    [[ ! -d "${SCRIPT_DIR}/kernel" ]] && missing+=("kernel")
    [[ ! -d "${SCRIPT_DIR}/mkbootimg" ]] && missing+=("mkbootimg")
    [[ ! -f "${SCRIPT_DIR}/oem_prebuilt_images/gki-ramdisk.lz4" ]] && missing+=("oem_prebuilt_images/gki-ramdisk.lz4")
    [[ ! -f "${SCRIPT_DIR}/custom_defconfigs/custom_defconfig" ]] && missing+=("custom_defconfigs/custom_defconfig")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required files:"
        printf '  - %s\n' "${missing[@]}"
        die "Required files missing"
    fi

    log_success "Prerequisites verified"
}

build_kernel() {
    log_info "Building kernel"
    cd "${SCRIPT_DIR}/kernel" || die "Cannot access kernel directory"

    ./build/build.sh 2>&1 | tee "${SCRIPT_DIR}/build.log"
    local build_result=${PIPESTATUS[0]}

    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"

    if [[ ${build_result} -ne 0 ]]; then
        log_warn "Build script returned error ${build_result}, checking outputs"
        local boot_img="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/boot.img"
        local kernel_img_gz="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"

        if [[ -f "${boot_img}" || -f "${kernel_img_gz}" ]]; then
            log_success "Build artifacts found, continuing"
        else
            die "Build failed, no artifacts found"
        fi
    fi

    mkdir -p "${SCRIPT_DIR}/dist"
    local boot_img="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/boot.img"
    local kernel_img_gz="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz"

    [[ -f "${boot_img}" ]] && cp "${boot_img}" "${SCRIPT_DIR}/dist/" && log_success "Copied boot.img"
    [[ -f "${kernel_img_gz}" ]] && cp "${kernel_img_gz}" "${SCRIPT_DIR}/dist/" && log_success "Copied Image.gz"

    log_success "Kernel build complete"
}

package_artifacts() {
    log_info "Packaging artifacts"
    cd "${SCRIPT_DIR}/dist" || die "Cannot access dist directory"

    if [[ ! -f "boot.img" ]]; then
        die "boot.img not found in dist directory"
    fi

    # PACKAGE_PREFIX is exported by the calling branch script:
    #   build-main.sh       -> KernelSU-NEXT
    #   build-susfs-dev.sh  -> SukiSU-Ultra
    local package_name="${PACKAGE_PREFIX:-SukiSU-Ultra}-A165F-${BUILD_KERNEL_VERSION}"
    log_info "Creating package with boot.img"

    tar -cvf "${package_name}.tar" boot.img || die "Tar creation failed"
    zip -9 "${package_name}-packaged.zip" "${package_name}.tar" || die "Zip creation failed"
    rm -f "${package_name}.tar" boot.img

    cd "${SCRIPT_DIR}" || die "Cannot return to script directory"
    log_success "Package created: ${SCRIPT_DIR}/dist/${package_name}-packaged.zip"
}

main() {
    local start_time end_time duration
    start_time=$(date +%s)

    log_info "====================================================================="
    log_info "SukiSU-Ultra Build Script"
    log_info "====================================================================="

    mkdir -p "${SCRIPT_DIR}/dist"
    check_and_install_requirements
    setup_toolchain
    fix_gen_build_config
    verify_prerequisites
    generate_build_config
    create_symlinks
    setup_environment
    build_kernel
    package_artifacts

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    log_info "====================================================================="
    log_success "Build completed in ${duration} seconds"
    log_info "====================================================================="
    log_info "Output: ${SCRIPT_DIR}/dist/${PACKAGE_PREFIX:-SukiSU-Ultra}-A165F-${BUILD_KERNEL_VERSION}-packaged.zip"
}

trap 'log_error "Build failed at line $LINENO"' ERR
main "$@"
BUILD_SH_EOF
  chmod +x build.sh
}

echo "==> Patching main branch"
git checkout main
write_shared_files
write_build_main
write_fixed_buildsh
rm -f .github/workflows/build.yml   # superseded by kernel_builder.yml
git add -A
git commit -m "ci: fix telegram env-var mismatch, branch-aware package name, dedupe scripts" || echo "(nothing to commit on main)"
git push origin main

echo "==> Patching susfs-dev branch"
git checkout susfs-dev
write_shared_files
write_build_susfs
write_fixed_buildsh
git add -A
git commit -m "ci: fix telegram env-var mismatch, sync fixed build.sh from main, dedupe scripts" || echo "(nothing to commit on susfs-dev)"
git push origin susfs-dev

git checkout "$ORIG_BRANCH"
echo "==> Done. Both branches patched and pushed."
