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
