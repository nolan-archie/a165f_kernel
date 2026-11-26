#!/usr/bin/env bash
# verify-susfs-symbols.sh
#
# Static pre-compile check: makes sure every susfs_* function called from
# the active KernelSU driver tree is actually declared/defined somewhere
# in-tree (SUSFS core files OR the driver's own headers/self-contained
# definitions). This is what would have caught the
# `susfs_is_current_proc_no_su` vs `susfs_is_current_proc_umounted`
# mismatch (build 32677869245) without needing a full kernel build.
#
# Heuristic (not a real C parser, so treat results as a strong signal,
# not proof):
#   "declared" = any susfs_* symbol appearing in *.h anywhere in scope,
#                OR any susfs_* symbol with a same-line function definition
#                (`susfs_name(...) {`) in *.c anywhere in scope.
#   "called"   = any susfs_* symbol referenced anywhere in *.c in the
#                driver tree.
# A symbol that's called but never declared will fail the real build with
# -Werror,-Wimplicit-function-declaration -- this check surfaces that before
# you spend a build cycle finding out.
#
# Usage:
#   ./verify-susfs-symbols.sh <kernel-5.10-dir> <kernelsu-driver-dir>
#
set -euo pipefail

KDIR="${1:?Usage: $0 <kernel-5.10-dir> <kernelsu-driver-dir>}"
KSU_DIR="${2:?Usage: $0 <kernel-5.10-dir> <kernelsu-driver-dir>}"

[ -d "$KDIR" ]    || { echo "[ERROR] $KDIR not found" >&2; exit 1; }
[ -d "$KSU_DIR" ] || { echo "[ERROR] $KSU_DIR not found (run select-kernelsu.sh first?)" >&2; exit 1; }

SUSFS_CORE_H=(
  "$KDIR/include/linux/susfs.h"
  "$KDIR/include/linux/susfs_def.h"
)
SUSFS_CORE_C="$KDIR/fs/susfs.c"
for f in "${SUSFS_CORE_H[@]}" "$SUSFS_CORE_C"; do
  [ -f "$f" ] || { echo "[ERROR] Expected SUSFS core file missing: $f" >&2; exit 1; }
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Comments can mention a SUSFS helper without calling it (for example,
# mount_hide.c documents SUSFS's private susfs_show_vfsmnt implementation).
# Scan comment-free copies so those notes are not mistaken for C references.
C_SCAN_DIR="$WORK_DIR/comment-free-c"
mkdir -p "$C_SCAN_DIR"
python3 - "$KSU_DIR" "$C_SCAN_DIR" <<'PY'
import sys
from pathlib import Path

source_root, output_root = map(Path, sys.argv[1:])

def strip_comments(text):
    out = []
    i = 0
    state = "code"
    quote = ""
    while i < len(text):
        char = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "line":
            if char == "\n":
                out.append(char)
                state = "code"
            else:
                out.append(" ")
        elif state == "block":
            if char == "*" and nxt == "/":
                out.extend("  ")
                i += 1
                state = "code"
            else:
                out.append("\n" if char == "\n" else " ")
        elif state == "string":
            out.append(char)
            if char == "\\" and nxt:
                out.append(nxt)
                i += 1
            elif char == quote:
                state = "code"
        elif char in ('"', "'"):
            quote = char
            state = "string"
            out.append(char)
        elif char == "/" and nxt == "/":
            out.extend("  ")
            i += 1
            state = "line"
        elif char == "/" and nxt == "*":
            out.extend("  ")
            i += 1
            state = "block"
        else:
            out.append(char)
        i += 1
    return "".join(out)

for source in source_root.rglob("*.c"):
    if source.is_file():
        destination = output_root / source.relative_to(source_root)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(strip_comments(source.read_text(errors="replace")))
PY

echo "[+] Scanning for declared susfs_* symbols (headers + same-line defs)..."
: > "$WORK_DIR/declared.txt"

# 1) Anything in a header, anywhere in scope (susfs core headers + all driver headers)
grep -rhoE '\bsusfs_[A-Za-z0-9_]+' "${SUSFS_CORE_H[@]}" 2>/dev/null >> "$WORK_DIR/declared.txt" || true
find -L "$KDIR/include" "$KSU_DIR" -name '*.h' -print0 2>/dev/null \
  | xargs -0 -r grep -hoE '\bsusfs_[A-Za-z0-9_]+' 2>/dev/null >> "$WORK_DIR/declared.txt" || true

# 2) #define macros (may live in .c or .h)
grep -rhoE '#define\s+susfs_[A-Za-z0-9_]+' "$SUSFS_CORE_C" "${SUSFS_CORE_H[@]}" 2>/dev/null \
  | awk '{print $2}' >> "$WORK_DIR/declared.txt" || true

# 3) Function definitions in .c files: real top-level defs start at column 0
#    with a type (`u32 susfs_x(void) {`), unlike indented call sites inside
#    if/while/for blocks (`    !susfs_x())\n{`). Anchoring on column 0 avoids
#    mistaking "call followed by a brace" for a definition.
grep -hoE '^[A-Za-z_][A-Za-z0-9_ \*]*\bsusfs_[A-Za-z0-9_]+\s*\(' "$SUSFS_CORE_C" 2>/dev/null \
  | grep -oE '\bsusfs_[A-Za-z0-9_]+' >> "$WORK_DIR/declared.txt" || true
find "$C_SCAN_DIR" -name '*.c' -print0 2>/dev/null \
  | xargs -0 -r grep -hoE '^[A-Za-z_][A-Za-z0-9_ \*]*\bsusfs_[A-Za-z0-9_]+\s*\(' 2>/dev/null \
  | grep -oE '\bsusfs_[A-Za-z0-9_]+' >> "$WORK_DIR/declared.txt" || true

sort -u -o "$WORK_DIR/declared.txt" "$WORK_DIR/declared.txt"
DECLARED_COUNT=$(wc -l < "$WORK_DIR/declared.txt")
echo "    $DECLARED_COUNT distinct susfs_* symbols found declared/defined"

# 4) Global variables declared at column 0 (`u32 susfs_x __read_mostly = 0;`,
#    `struct work_struct susfs_x;`) -- these are referenced without a `(`
#    and would otherwise false-positive as "called but undeclared".
grep -hoE '^[A-Za-z_][A-Za-z0-9_ \*]*\bsusfs_[A-Za-z0-9_]+\s*[;=\[]' "$SUSFS_CORE_C" 2>/dev/null \
  | grep -oE '\bsusfs_[A-Za-z0-9_]+' >> "$WORK_DIR/declared.txt" || true
find "$C_SCAN_DIR" -name '*.c' -print0 2>/dev/null \
  | xargs -0 -r grep -hoE '^[A-Za-z_][A-Za-z0-9_ \*]*\bsusfs_[A-Za-z0-9_]+\s*[;=\[]' 2>/dev/null \
  | grep -oE '\bsusfs_[A-Za-z0-9_]+' >> "$WORK_DIR/declared.txt" || true
sort -u -o "$WORK_DIR/declared.txt" "$WORK_DIR/declared.txt"

echo "[+] Scanning for susfs_* FUNCTIONS called from $KSU_DIR/*.c ..."
# Only symbols used in call syntax (name followed by '(') count as "called" --
# bare variable references (no paren) are a different class of usage and are
# checked separately below.
find "$C_SCAN_DIR" -name '*.c' -print0 2>/dev/null \
  | xargs -0 -r grep -hoE '\bsusfs_[A-Za-z0-9_]+\s*\(' 2>/dev/null \
  | sed -E 's/\s*\($//' \
  | sort -u > "$WORK_DIR/called.txt" || true
CALLED_COUNT=$(wc -l < "$WORK_DIR/called.txt")
echo "    $CALLED_COUNT distinct susfs_* symbols referenced"

echo "[+] Cross-checking..."
MISSING=$(comm -23 "$WORK_DIR/called.txt" "$WORK_DIR/declared.txt")

# SukiSU builtin-new can consume these optional APIs when a newer SUSFS core
# defines the matching commands. This kernel's SUSFS v2.3.0 does not provide
# those commands; every downstream call is guarded by the missing command
# macro, and the defconfig leaves priority UID filtering disabled.
if ! grep -Eq '^#define[[:space:]]+CMD_SUSFS_SET_PRIORITY_UID_FILTER\b' \
     "$KDIR/include/linux/susfs.h" "$KDIR/include/linux/susfs_def.h"; then
  MISSING="$(printf '%s\n' "$MISSING" | grep -Ev '^(susfs_parse_priority_app_strings|susfs_set_priority_uid_filter)$' || true)"
fi
if ! grep -Eq '^#define[[:space:]]+CMD_SUSFS_SET_SUS_PATH_UID_FILTER\b' \
     "$KDIR/include/linux/susfs.h" "$KDIR/include/linux/susfs_def.h"; then
  MISSING="$(printf '%s\n' "$MISSING" | grep -Ev '^(susfs_parse_sus_path_app_strings|susfs_set_sus_path_uid_filter)$' || true)"
fi

if [ -z "$MISSING" ]; then
  echo
  echo "[PASS] Every susfs_* symbol referenced in $KSU_DIR is declared/defined somewhere in scope."
  exit 0
else
  echo
  echo "[FAIL] susfs_* symbols referenced but never declared/defined in scope."
  echo "       These will fail with -Werror,-Wimplicit-function-declaration:"
  echo
  while read -r sym; do
    echo "  - $sym"
    PREFIX="${sym:0:$((${#sym}>14?14:${#sym}))}"
    CLOSEST="$(grep -i "$PREFIX" "$WORK_DIR/declared.txt" 2>/dev/null | grep -v "^${sym}$" | head -3 || true)"
    [ -n "$CLOSEST" ] && echo "$CLOSEST" | sed 's/^/      possible rename: /'
    find -L "$KSU_DIR" -name '*.c' -exec grep -l "\b$sym\b" {} \; 2>/dev/null \
      | sed 's/^/      called from: /' || true
  done <<< "$MISSING"
  echo
  exit 1
fi
