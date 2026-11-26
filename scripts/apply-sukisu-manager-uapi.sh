#!/usr/bin/env bash
# Verify the pinned SukiSU Nova builtin-new UAPI and manager integration.
set -euo pipefail

REPO_ROOT="${1:?Usage: $0 <repository-root>}"
source "$REPO_ROOT/scripts/sukisu-upstream.env"

KSU_ROOT="$REPO_ROOT/kernel-5.10/KernelSU/kernel"
HEADER="$KSU_ROOT/include/uapi/supercall.h"
EXT_HEADER="$KSU_ROOT/include/uapi/extension.h"
DISPATCH="$KSU_ROOT/supercall/dispatch.c"
UNIFIED_SOURCE="$KSU_ROOT/ksu.c"
EXTENSION_SOURCE="$KSU_ROOT/extension/extension.c"
DYNAMIC_MANAGER="$KSU_ROOT/extension/dynamic_manager.c"
BOOT_EVENT="$KSU_ROOT/runtime/boot_event.c"
MAKEFILE="$KSU_ROOT/Makefile"

for file in "$HEADER" "$EXT_HEADER" "$DISPATCH" "$UNIFIED_SOURCE" \
            "$EXTENSION_SOURCE" "$DYNAMIC_MANAGER" "$BOOT_EVENT" "$MAKEFILE"; do
  if [[ ! -f "$file" ]]; then
    echo "[compat] Required SukiSU Nova source is missing: ${file#"$REPO_ROOT"/}" >&2
    exit 1
  fi
done

# The package observer only does a full manager scan when packages.list is
# renamed. A kernel-only reboot can leave it untouched, so scan at boot
# completion as well. Apply this after every weekly upstream sync.
python3 - "$BOOT_EVENT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
start = source.find("void on_boot_completed(void)")
end = source.find("\n}", start)
if start < 0 or end < 0:
    raise SystemExit("[compat] Could not locate on_boot_completed() in boot_event.c.")

function = source[start:end + 2]
prune_only = "\ttrack_throne(true);"
full_scan = "\ttrack_throne(false);"
if function.count(prune_only) == 1:
    function = function.replace(
        prune_only,
        "\t/* A kernel-only reboot may leave packages.list unchanged. */\n" + full_scan,
        1,
    )
elif function.count(full_scan) != 1:
    raise SystemExit("[compat] Unexpected manager scan in on_boot_completed().")

path.write_text(source[:start] + function + source[end + 2:])
PY

uapi_version="$(sed -nE 's/^[[:space:]]*#define[[:space:]]+KERNEL_SU_UAPI_VERSION[[:space:]]+([0-9]+).*/\1/p' "$HEADER" | head -n1)"
if [[ "$uapi_version" != 6 ]]; then
  echo "[compat] Expected SukiSU builtin-new UAPI v6, found '${uapi_version:-missing}'." >&2
  exit 1
fi

if ! grep -Eq '^#define[[:space:]]+KSU_IOCTL_EXTENSION\b' "$EXT_HEADER" || \
   ! grep -Eq 'KSU_EXTENSION_DYNAMIC_MANAGER[[:space:]]*=[[:space:]]*3' "$EXT_HEADER" || \
   ! grep -Fq 'ksu_extension_dynamic_manager_io' "$DYNAMIC_MANAGER" || \
   ! grep -Fq '.io_handler = ksu_extension_dynamic_manager_io' "$EXTENSION_SOURCE";
then
  echo "[compat] The builtin-new dynamic-manager extension API is incomplete." >&2
  exit 1
fi

if ! grep -Fq '#include "extension/dynamic_manager.c"' "$UNIFIED_SOURCE" || \
   ! grep -Fq 'ksu_extension_register_all();' "$UNIFIED_SOURCE" || \
   ! grep -Fq 'KSU_EXTENSION_DYNAMIC_MANAGER' "$EXTENSION_SOURCE";
then
  echo "[compat] The builtin-new extension hub is not linked and initialized." >&2
  exit 1
fi

manager_load_line="$(grep -nF 'ksu_dynamic_manager_load();' "$UNIFIED_SOURCE" | head -n1 | cut -d: -f1)"
tracker_init_line="$(grep -nF 'ksu_throne_tracker_init();' "$UNIFIED_SOURCE" | head -n1 | cut -d: -f1)"
if [[ ! "$manager_load_line" =~ ^[0-9]+$ || ! "$tracker_init_line" =~ ^[0-9]+$ ]] || \
   (( manager_load_line >= tracker_init_line )); then
  echo "[compat] Dynamic managers must be loaded before the throne tracker starts." >&2
  exit 1
fi

if ! grep -Eq 'KSU_PACKAGE_NAME[[:space:]]*:?=[[:space:]]*com\.sukisu\.nova([[:space:]]|$)' "$MAKEFILE" || \
   ! grep -Fq 'KSU_EXPECTED_SIZE := 0x35c' "$MAKEFILE" || \
   ! grep -Fq 'KSU_EXPECTED_HASH := 947ae944f3de4ed4c21a7e4f7953ecf351bfa2b36239da37a34111ad29993eef' "$MAKEFILE";
then
  echo "[compat] SukiSU Nova package name or manager signer expectations do not match upstream." >&2
  exit 1
fi

if ! grep -Eq '^config KSU_SUSFS$' "$KSU_ROOT/Kconfig" || \
   ! grep -Eq '^config KSU_SUSFS_INLINE_HOOK$' "$KSU_ROOT/Kconfig";
then
  echo "[compat] Upstream SukiSU SUSFS inline-hook Kconfig support is missing." >&2
  exit 1
fi

echo "[compat] Verified SukiSU Nova $SUKISU_BRANCH at $SUKISU_COMMIT, UAPI v$uapi_version, dynamic-manager extension, and manager identity."
