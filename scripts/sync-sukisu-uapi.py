#!/usr/bin/env python3
"""Sync the SukiSU UAPI, event handlers, and dynamic manager ioctl."""

from __future__ import annotations

import re
import sys
from pathlib import Path


DECLARE_MACRO = """#ifdef __BINDGEN__
#define DECLARE(type, name, val) static const type name = val
#else
#define DECLARE(type, name, val) enum { name = val }
#endif
"""


def fail(message: str) -> None:
    raise SystemExit(f"[uapi-sync] {message}")


def strip_c_comments(source: str) -> str:
    """Remove comments without changing string or character literals."""
    chars = list(source)
    state = "code"
    i = 0
    while i < len(source):
        char = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if char == "/" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "line_comment"
                continue
            if char == "/" and nxt == "*":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "block_comment"
                continue
            if char == '"':
                state = "string"
            elif char == "'":
                state = "char"
            i += 1
            continue
        if state == "line_comment":
            if char == "\n":
                state = "code"
            else:
                chars[i] = " "
            i += 1
            continue
        if state == "block_comment":
            if char == "*" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "code"
            else:
                if char != "\n":
                    chars[i] = " "
                i += 1
            continue
        if char == "\\":
            i += 2
            continue
        if (state == "string" and char == '"') or (state == "char" and char == "'"):
            state = "code"
        i += 1
    return "".join(chars)


def convert_uapi(source: str) -> str:
    """Adapt upstream static constants to the local bindgen-aware form."""
    if "#define DECLARE" in source:
        if "KERNEL_SU_UAPI_VERSION" not in source:
            fail("upstream supercall.h has no UAPI version declaration")
        return source

    declaration = re.compile(
        r"^(\s*)static const ([A-Za-z_]\w*) ([A-Za-z_]\w*) = "
        r"(.*?);([ \t]*(?://.*|/\*.*\*/)?[ \t]*)$"
    )
    output_lines: list[str] = []
    converted = 0
    for line in source.splitlines():
        match = declaration.match(line)
        if match:
            indent, ctype, name, value, comment = match.groups()
            line = f"{indent}DECLARE({ctype}, {name}, {value});{comment}"
            converted += 1
        elif "static const" in line:
            fail(f"cannot adapt upstream UAPI declaration: {line.strip()}")
        output_lines.append(line)

    if converted == 0:
        fail("upstream supercall.h contains no adaptable UAPI constants")

    include_indexes = [
        index for index, line in enumerate(output_lines)
        if re.match(r"^\s*#include\b", line)
    ]
    if not include_indexes:
        fail("upstream supercall.h has no includes for the DECLARE adapter")
    output_lines[include_indexes[-1] + 1:include_indexes[-1] + 1] = [
        "",
        *DECLARE_MACRO.rstrip().splitlines(),
    ]

    result = "\n".join(output_lines) + "\n"
    if not re.search(
        r"DECLARE\(\s*__u32\s*,\s*KERNEL_SU_UAPI_VERSION\s*,\s*\d+\s*\)",
        result,
    ):
        fail("upstream supercall.h has no numeric KERNEL_SU_UAPI_VERSION")
    return result


def declared_constants(header: str) -> dict[str, str]:
    masked = mask_comments_and_strings(header)
    declarations = {}
    for match in re.finditer(r"^[ \t]*DECLARE\(", masked, flags=re.MULTILINE):
        end = masked.find(";", match.start())
        if end < 0:
            fail("unterminated DECLARE() in UAPI header")
        statement = masked[match.start():end + 1]
        name = re.match(
            r"^[ \t]*DECLARE\(\s*[^,\n]+?\s*,\s*([A-Za-z_]\w*)",
            statement,
        )
        if name:
            raw = header[match.start():end + 1]
            declarations[name.group(1)] = re.sub(
                r"\s+", "", strip_c_comments(raw)
            )
    return declarations


def structure_declarations(header: str) -> list[tuple[int, str, str, str]]:
    masked = mask_comments_and_strings(header)
    structures = []
    for match in re.finditer(r"\bstruct\s+([A-Za-z_]\w*)\s*\{", masked):
        open_pos = masked.find("{", match.start(), match.end())
        close_pos = matching_brace(header, open_pos, masked)
        end = close_pos + 1
        while end < len(masked) and masked[end].isspace():
            end += 1
        if end < len(masked) and masked[end] == ";":
            end += 1
            raw = header[match.start():end]
            normalized = re.sub(r"\b__user\b", "", masked[match.start():end])
            structures.append((match.start(), match.group(1), raw, re.sub(r"\s+", "", normalized)))
    return structures


def declared_structures(header: str) -> dict[str, str]:
    return {name: definition for _, name, _, definition in structure_declarations(header)}


def append_upstream_declarations(local_header: str, upstream_header: str) -> tuple[str, list[str]]:
    """Add new upstream constants/structs while preserving local-only ABI items."""
    local_constants = declared_constants(local_header)
    local_structs = declared_structures(local_header)
    masked = mask_comments_and_strings(upstream_header)
    additions: list[tuple[int, str, str]] = []

    for match in re.finditer(r"^[ \t]*DECLARE\(", masked, flags=re.MULTILINE):
        end = masked.find(";", match.start())
        if end < 0:
            fail("unterminated upstream DECLARE()")
        statement = masked[match.start():end + 1]
        name = re.match(
            r"^[ \t]*DECLARE\(\s*[^,\n]+?\s*,\s*([A-Za-z_]\w*)",
            statement,
        )
        if not name:
            continue
        symbol = name.group(1)
        if symbol == "KERNEL_SU_UAPI_VERSION" or symbol.startswith("EVENT_"):
            continue
        if symbol not in local_constants:
            raw = upstream_header[match.start():end + 1].rstrip()
            additions.append((match.start(), symbol, raw))
            local_constants[symbol] = re.sub(r"\s+", "", statement)

    for offset, name, raw, _ in structure_declarations(upstream_header):
        if name not in local_structs:
            additions.append((offset, f"struct {name}", raw.rstrip()))
            local_structs[name] = ""

    additions.sort(key=lambda item: item[0])
    if not additions:
        return local_header, []

    endif_matches = list(re.finditer(r"^[ \t]*#endif\b", local_header, flags=re.MULTILINE))
    if not endif_matches:
        fail("could not find the final include guard in the local UAPI header")

    insert_at = endif_matches[-1].start()
    prefix = local_header[:insert_at].rstrip()
    suffix = local_header[insert_at:]
    names = [name for _, name, _ in additions]
    block = "\n\n/* Additive declarations imported from SukiSU-Ultra/main. */\n"
    block += "\n\n".join(raw for _, _, raw in additions)
    return prefix + block + "\n\n" + suffix, names


def validate_non_event_contract(local_header: str, upstream_header: str) -> None:
    """Require every upstream ABI item while allowing local-only extensions."""
    local_includes = set(
        re.findall(r"^\s*#include\s+[^\n]+", local_header, flags=re.MULTILINE)
    )
    upstream_includes = set(
        re.findall(r"^\s*#include\s+[^\n]+", upstream_header, flags=re.MULTILINE)
    )
    missing_includes = sorted(upstream_includes - local_includes)

    local_constants = declared_constants(local_header)
    upstream_constants = declared_constants(upstream_header)
    incompatible = []
    for name, definition in upstream_constants.items():
        if name == "KERNEL_SU_UAPI_VERSION" or name.startswith("EVENT_"):
            continue
        if name in local_constants and local_constants[name] != definition:
            incompatible.append(name)

    local_structures = declared_structures(local_header)
    upstream_structures = declared_structures(upstream_header)
    for name, definition in upstream_structures.items():
        if name in local_structures and local_structures[name] != definition:
            incompatible.append(f"struct {name}")

    if missing_includes:
        incompatible.extend(f"include {item}" for item in missing_includes)
    if incompatible:
        fail(
            "upstream non-event UAPI items are missing or different in the "
            "kernel tree: " + ", ".join(sorted(incompatible))
        )


def merge_manager_uapi(local_header: str, upstream_header: str) -> str:
    """Merge the manager header include and dynamic-manager ioctl."""
    manager_include = '#include "uapi/manager.h"'
    if not re.search(r'^\s*#include\s+"uapi/manager\.h"\s*$', upstream_header, re.MULTILINE):
        fail('upstream supercall.h no longer includes "uapi/manager.h"')

    upstream_constants = declared_constants(upstream_header)
    manager_ioctl = upstream_constants.get("KSU_IOCTL_MANAGER")
    if not manager_ioctl:
        fail("upstream supercall.h has no KSU_IOCTL_MANAGER declaration")

    local_constants = declared_constants(local_header)
    local_ioctl = local_constants.get("KSU_IOCTL_MANAGER")
    if local_ioctl and local_ioctl != manager_ioctl:
        fail("local KSU_IOCTL_MANAGER declaration differs from upstream")

    lines = local_header.splitlines()
    if manager_include not in {
        re.sub(r"\s+", " ", line.strip()) for line in lines
    }:
        app_profile_include = next(
            (
                index for index, line in enumerate(lines)
                if re.match(r'^\s*#include\s+"uapi/app_profile\.h"\s*$', line)
            ),
            None,
        )
        if app_profile_include is None:
            fail('could not find a place for the "uapi/manager.h" include')
        lines.insert(app_profile_include + 1, manager_include)

    if not local_ioctl:
        ioctl_line = next(
            (
                line for line in upstream_header.splitlines()
                if re.search(
                    r"DECLARE\(\s*__u32\s*,\s*KSU_IOCTL_MANAGER\s*,",
                    line,
                )
            ),
            None,
        )
        if ioctl_line is None:
            fail("could not find the upstream KSU_IOCTL_MANAGER declaration")
        kpm_index = next(
            (
                index for index, line in enumerate(lines)
                if re.search(r"DECLARE\(\s*__u32\s*,\s*KSU_IOCTL_KPM\s*,", line)
            ),
            None,
        )
        if kpm_index is None:
            fail("could not find a place for KSU_IOCTL_MANAGER")
        lines.insert(kpm_index, ioctl_line)

    return "\n".join(lines) + "\n"


def merge_uapi_header(local_header: str, upstream_header: str) -> str:
    """Update the version/events and import additive upstream ABI declarations."""
    version = re.search(
        r"DECLARE\(\s*__u32\s*,\s*KERNEL_SU_UAPI_VERSION\s*,\s*(\d+)\s*\)",
        upstream_header,
    )
    if not version:
        fail("upstream supercall.h has no numeric KERNEL_SU_UAPI_VERSION")

    upstream_event_lines = []
    for line in upstream_header.splitlines():
        if re.search(r"DECLARE\(\s*__u32\s*,\s*EVENT_[A-Z0-9_]+\s*,", line):
            upstream_event_lines.append(line)
    if not upstream_event_lines:
        fail("upstream supercall.h has no EVENT_* declarations")

    local_header, additions = append_upstream_declarations(local_header, upstream_header)
    if additions:
        print("[uapi-sync] imported additive UAPI declarations: " + ", ".join(additions))

    local_lines = local_header.splitlines()
    local_event_indexes = [
        index for index, line in enumerate(local_lines)
        if re.search(r"DECLARE\(\s*__u32\s*,\s*EVENT_[A-Z0-9_]+\s*,", line)
    ]
    if local_event_indexes:
        event_insert_at = local_event_indexes[0]
    else:
        daemon_struct = next(
            (
                index for index, line in enumerate(local_lines)
                if "struct ksu_become_daemon_cmd" in line
            ),
            None,
        )
        if daemon_struct is None:
            fail("could not find a place for upstream event declarations")
        event_insert_at = next(
            (
                index + 1 for index in range(daemon_struct, len(local_lines))
                if local_lines[index].strip() == "};"
            ),
            None,
        )
        if event_insert_at is None:
            fail("could not find the end of ksu_become_daemon_cmd")

    output = []
    inserted_events = False
    version_seen = False
    for index, line in enumerate(local_lines):
        if index == event_insert_at:
            output.extend(upstream_event_lines)
            inserted_events = True

        if re.search(r"DECLARE\(\s*__u32\s*,\s*EVENT_[A-Z0-9_]+\s*,", line):
            continue

        version_line = re.match(
            r"^(\s*DECLARE\(\s*__u32\s*,\s*KERNEL_SU_UAPI_VERSION\s*,\s*)"
            r"\d+(\s*\);.*)$",
            line,
        )
        if version_line:
            line = f"{version_line.group(1)}{version.group(1)}{version_line.group(2)}"
            version_seen = True
        output.append(line)

    if not inserted_events:
        output.extend(upstream_event_lines)
    if not version_seen:
        fail("could not find KERNEL_SU_UAPI_VERSION in the local header")
    return "\n".join(output) + "\n"


def mask_comments_and_strings(source: str) -> str:
    """Blank comments and literals while preserving offsets and newlines."""
    chars = list(source)
    i = 0
    state = "code"
    while i < len(source):
        char = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""

        if state == "code":
            if char == "/" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "line_comment"
                continue
            if char == "/" and nxt == "*":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "block_comment"
                continue
            if char == '"':
                chars[i] = " "
                state = "string"
            elif char == "'":
                chars[i] = " "
                state = "char"
            i += 1
            continue

        if state == "line_comment":
            if char == "\n":
                state = "code"
            else:
                chars[i] = " "
            i += 1
            continue

        if state == "block_comment":
            if char == "*" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "code"
            else:
                if char != "\n":
                    chars[i] = " "
                i += 1
            continue

        if char == "\\":
            chars[i] = " "
            if i + 1 < len(source):
                if source[i + 1] != "\n":
                    chars[i + 1] = " "
                i += 2
            else:
                i += 1
            continue
        if (state == "string" and char == '"') or (state == "char" and char == "'"):
            chars[i] = " "
            state = "code"
        elif char != "\n":
            chars[i] = " "
        i += 1

    return "".join(chars)


def matching_brace(source: str, open_pos: int, masked: str | None = None) -> int:
    masked = masked if masked is not None else mask_comments_and_strings(source)
    if open_pos >= len(masked) or masked[open_pos] != "{":
        fail("internal parser error: expected opening brace")
    depth = 0
    for index in range(open_pos, len(masked)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    fail("unbalanced braces in SukiSU dispatch source")


def extract_event_function(source: str) -> tuple[int, int, str]:
    masked = mask_comments_and_strings(source)
    match = re.search(
        r"\bstatic\s+int\s+do_report_event\s*\([^)]*\)\s*\{",
        masked,
    )
    if not match:
        fail("could not find do_report_event()")
    open_pos = match.end() - 1
    close_pos = matching_brace(source, open_pos, masked)
    return match.start(), close_pos + 1, source[match.start():close_pos + 1]


def extract_static_int_function(source: str, name: str) -> tuple[int, int, str]:
    masked = mask_comments_and_strings(source)
    match = re.search(
        rf"\bstatic\s+int\s+{re.escape(name)}\s*\([^)]*\)\s*\{{",
        masked,
    )
    if not match:
        fail(f"could not find {name}()")
    open_pos = match.end() - 1
    close_pos = matching_brace(source, open_pos, masked)
    return match.start(), close_pos + 1, source[match.start():close_pos + 1]


def extract_ioctl_entry(source: str, command: str) -> tuple[int, int, str]:
    masked = mask_comments_and_strings(source)
    table = re.search(
        r"static\s+const\s+struct\s+ksu_ioctl_cmd_map\s+"
        r"ksu_ioctl_handlers\s*\[\s*\]\s*=\s*\{",
        masked,
    )
    if not table:
        fail("could not find ksu_ioctl_handlers[]")
    table_open = table.end() - 1
    table_close = matching_brace(source, table_open, masked)

    cursor = table_open + 1
    while cursor < table_close:
        if masked[cursor] != "{":
            cursor += 1
            continue
        entry_end = matching_brace(source, cursor, masked)
        if re.search(
            rf"\.cmd\s*=\s*{re.escape(command)}\b",
            masked[cursor:entry_end + 1],
        ):
            return cursor, entry_end + 1, source[cursor:entry_end + 1]
        cursor = entry_end + 1

    fail(f"{command} has no entry in ksu_ioctl_handlers[]")


def merge_manager_dispatch(
    upstream_dispatch: str,
    local_dispatch: str,
) -> str:
    """Import do_manager() and its permission-checked ioctl map entry."""
    _, _, upstream_function = extract_static_int_function(
        upstream_dispatch, "do_manager"
    )
    if (
        "ksu_dynamic_manager_get" not in upstream_function
        or "ksu_dynamic_manager_set" not in upstream_function
    ):
        fail("upstream do_manager() does not implement GET and mutation operations")

    _, _, upstream_entry = extract_ioctl_entry(
        upstream_dispatch, "KSU_IOCTL_MANAGER"
    )
    if not re.search(r"\.handler\s*=\s*do_manager\b", upstream_entry):
        fail("upstream KSU_IOCTL_MANAGER entry has no do_manager() handler")
    if not re.search(r"\.perm_check\s*=\s*manager_or_root\b", upstream_entry):
        fail("upstream KSU_IOCTL_MANAGER entry has unexpected permissions")

    if re.search(
        r"\bstatic\s+int\s+do_manager\s*\(",
        mask_comments_and_strings(local_dispatch),
    ):
        local_start, local_end, local_function = extract_static_int_function(
            local_dispatch, "do_manager"
        )
    else:
        local_function = None
    if local_function is None:
        masked = mask_comments_and_strings(local_dispatch)
        anchor = re.search(
            r"(?=\bstatic\s+int\s+do_set_sepolicy\s*\()", masked
        )
        if not anchor:
            fail("could not find a place for do_manager()")
        local_dispatch = (
            local_dispatch[:anchor.start()]
            + upstream_function
            + "\n\n"
            + local_dispatch[anchor.start():]
        )
    else:
        local_dispatch = (
            local_dispatch[:local_start]
            + upstream_function
            + local_dispatch[local_end:]
        )

    if re.search(
        r"\.cmd\s*=\s*KSU_IOCTL_MANAGER\b",
        mask_comments_and_strings(local_dispatch),
    ):
        _, _, local_entry = extract_ioctl_entry(
            local_dispatch, "KSU_IOCTL_MANAGER"
        )
    else:
        local_entry = None
    if local_entry is not None:
        if not re.search(r"\.handler\s*=\s*do_manager\b", local_entry):
            fail("local KSU_IOCTL_MANAGER entry has an unexpected handler")
        if not re.search(r"\.perm_check\s*=\s*manager_or_root\b", local_entry):
            fail("local KSU_IOCTL_MANAGER entry has unexpected permissions")
    else:
        masked = mask_comments_and_strings(local_dispatch)
        table = re.search(
            r"static\s+const\s+struct\s+ksu_ioctl_cmd_map\s+"
            r"ksu_ioctl_handlers\s*\[\s*\]\s*=\s*\{",
            masked,
        )
        if not table:
            fail("could not find ksu_ioctl_handlers[]")
        table_open = table.end() - 1
        table_close = matching_brace(local_dispatch, table_open, masked)
        sentinel = re.search(
            r"\{\s*\.cmd\s*=\s*0\b",
            masked[table_open + 1:table_close],
        )
        if not sentinel:
            fail("could not find the ioctl map sentinel")
        insert_at = table_open + 1 + sentinel.start()
        local_dispatch = (
            local_dispatch[:insert_at]
            + upstream_entry
            + ",\n    "
            + local_dispatch[insert_at:]
        )

    if '#include "manager/dynamic_manager.h"' not in local_dispatch:
        local_dispatch = '#include "manager/dynamic_manager.h"\n\n' + local_dispatch
    return local_dispatch


def merge_lookup_symbols_dispatch(
    upstream_dispatch: str,
    local_dispatch: str,
) -> str:
    """Import the UAPI v6 symbol lookup handler and its permission-checked ioctl."""
    _, _, upstream_function = extract_static_int_function(
        upstream_dispatch, "do_lookup_symbols"
    )
    if (
        "ksu_lookup_kernel_symbols" not in upstream_function
        or "KSU_LOOKUP_SYMBOLS_MAX" not in upstream_function
    ):
        fail("upstream do_lookup_symbols() does not implement the v6 lookup contract")

    _, _, upstream_entry = extract_ioctl_entry(
        upstream_dispatch, "KSU_IOCTL_LOOKUP_SYMBOLS"
    )
    if not re.search(r"\.handler\s*=\s*do_lookup_symbols\b", upstream_entry):
        fail("upstream KSU_IOCTL_LOOKUP_SYMBOLS entry has no lookup handler")
    if not re.search(r"\.perm_check\s*=\s*only_root\b", upstream_entry):
        fail("upstream KSU_IOCTL_LOOKUP_SYMBOLS entry has unexpected permissions")

    masked = mask_comments_and_strings(local_dispatch)
    if re.search(r"\bstatic\s+int\s+do_lookup_symbols\s*\(", masked):
        local_start, local_end, local_function = extract_static_int_function(
            local_dispatch, "do_lookup_symbols"
        )
        if "ksu_lookup_kernel_symbols" not in local_function:
            fail("local do_lookup_symbols() has an unexpected implementation")
        local_dispatch = (
            local_dispatch[:local_start]
            + upstream_function
            + local_dispatch[local_end:]
        )
    else:
        anchor = re.search(
            r"(?=static\s+const\s+struct\s+ksu_ioctl_cmd_map\s+"
            r"ksu_ioctl_handlers\s*\[\s*\]\s*=\s*\{)",
            masked,
        )
        if not anchor:
            fail("could not find ksu_ioctl_handlers[] for do_lookup_symbols()")
        local_dispatch = (
            local_dispatch[:anchor.start()]
            + upstream_function
            + "\n\n"
            + local_dispatch[anchor.start():]
        )

    masked = mask_comments_and_strings(local_dispatch)
    if re.search(r"\.cmd\s*=\s*KSU_IOCTL_LOOKUP_SYMBOLS\b", masked):
        entry_start, entry_end, local_entry = extract_ioctl_entry(
            local_dispatch, "KSU_IOCTL_LOOKUP_SYMBOLS"
        )
        if not re.search(r"\.handler\s*=\s*do_lookup_symbols\b", local_entry):
            fail("local KSU_IOCTL_LOOKUP_SYMBOLS entry has an unexpected handler")
        if not re.search(r"\.perm_check\s*=\s*only_root\b", local_entry):
            fail("local KSU_IOCTL_LOOKUP_SYMBOLS entry has unexpected permissions")
        local_dispatch = (
            local_dispatch[:entry_start]
            + upstream_entry
            + local_dispatch[entry_end:]
        )
    else:
        table = re.search(
            r"static\s+const\s+struct\s+ksu_ioctl_cmd_map\s+"
            r"ksu_ioctl_handlers\s*\[\s*\]\s*=\s*\{",
            masked,
        )
        if not table:
            fail("could not find ksu_ioctl_handlers[]")
        table_open = table.end() - 1
        table_close = matching_brace(local_dispatch, table_open, masked)
        table_body = masked[table_open + 1:table_close]
        anchor = re.search(r"\{\s*\.cmd\s*=\s*0\b", table_body)
        if not anchor:
            fail("could not find the ioctl map sentinel for KSU_IOCTL_LOOKUP_SYMBOLS")
        insert_at = table_open + 1 + anchor.start()
        local_dispatch = (
            local_dispatch[:insert_at]
            + upstream_entry
            + ",\n    "
            + local_dispatch[insert_at:]
        )

    if '#include "infra/symbol_resolver.h"' not in local_dispatch:
        local_dispatch = '#include "infra/symbol_resolver.h"\n' + local_dispatch
    return local_dispatch


def event_cases(function: str) -> tuple[list[tuple[str, int, int]], int]:
    masked = mask_comments_and_strings(function)
    switch = re.search(r"\bswitch\s*\(\s*cmd\.event\s*\)\s*\{", masked)
    if not switch:
        fail("do_report_event() has no switch(cmd.event)")
    open_pos = switch.end() - 1
    close_pos = matching_brace(function, open_pos, masked)
    body_start = open_pos + 1
    body = masked[body_start:close_pos]

    labels: list[tuple[str, int]] = []
    depth = 0
    offset = 0
    for line in body.splitlines(keepends=True):
        if depth == 0:
            label = re.match(
                r"^[ \t]*(?:case\s+(EVENT_[A-Z0-9_]+)\s*:|(default)\s*:)",
                line,
            )
            if label:
                name = label.group(1) or "default"
                labels.append((name, body_start + offset))
        depth += line.count("{") - line.count("}")
        offset += len(line)

    cases = [
        (name, start, labels[index + 1][1] if index + 1 < len(labels) else close_pos)
        for index, (name, start) in enumerate(labels)
        if name != "default"
    ]
    default_positions = [start for name, start in labels if name == "default"]
    return cases, default_positions[0] if default_positions else close_pos


def merge_event_cases(
    upstream_header: str,
    upstream_dispatch: str,
    local_dispatch: str,
) -> str:
    declared_events = set(
        re.findall(
            r"DECLARE\(\s*__u32\s*,\s*(EVENT_[A-Z0-9_]+)\s*,",
            upstream_header,
        )
    )
    if not declared_events:
        fail("no EVENT_* values found in upstream supercall.h")

    _, _, upstream_function = extract_event_function(upstream_dispatch)
    upstream_cases, _ = event_cases(upstream_function)
    upstream_case_names = {name for name, _, _ in upstream_cases}
    if declared_events != upstream_case_names:
        missing = sorted(declared_events - upstream_case_names)
        undeclared = sorted(upstream_case_names - declared_events)
        details = []
        if missing:
            details.append("no upstream handler for " + ", ".join(missing))
        if undeclared:
            details.append("handler uses undeclared " + ", ".join(undeclared))
        fail("upstream event contract is inconsistent: " + "; ".join(details))

    local_start, local_end, local_function = extract_event_function(local_dispatch)
    local_cases, _ = event_cases(local_function)

    # Remove cases for events upstream has retired; their constants no longer
    # exist in the synced UAPI, so retaining them would break compilation.
    stale_ranges = [
        (start, end)
        for name, start, end in local_cases
        if name not in declared_events
    ]
    for start, end in reversed(stale_ranges):
        local_function = local_function[:start] + local_function[end:]

    local_cases, default_pos = event_cases(local_function)
    local_names = {name for name, _, _ in local_cases}
    upstream_case_map = {name: (start, end) for name, start, end in upstream_cases}
    missing_names = [
        name for name, _, _ in upstream_cases
        if name not in local_names
    ]

    if missing_names:
        additions = []
        for name in missing_names:
            start, end = upstream_case_map[name]
            additions.append(upstream_function[start:end].rstrip())
        insertion = "\n".join(additions) + "\n"
        prefix = local_function[:default_pos]
        if prefix and not prefix.endswith("\n"):
            prefix += "\n"
        local_function = prefix + insertion + local_function[default_pos:]

    return local_dispatch[:local_start] + local_function + local_dispatch[local_end:]


def write_if_changed(path: Path, contents: str) -> bool:
    if path.read_text() == contents:
        return False
    path.write_text(contents)
    return True


def main() -> None:
    if len(sys.argv) != 5:
        fail(
            "usage: sync-sukisu-uapi.py <upstream-supercall.h> "
            "<upstream-dispatch.c> <local-supercall.h> <local-dispatch.c>"
        )

    upstream_header_path, upstream_dispatch_path, local_header_path, local_dispatch_path = map(
        Path, sys.argv[1:]
    )
    for path in (
        upstream_header_path,
        upstream_dispatch_path,
        local_header_path,
        local_dispatch_path,
    ):
        if not path.is_file():
            fail(f"required source file is missing: {path}")

    previous_header = local_header_path.read_text()
    upstream_header = convert_uapi(upstream_header_path.read_text())
    merged_manager_header = merge_manager_uapi(previous_header, upstream_header)
    validate_non_event_contract(merged_manager_header, upstream_header)
    merged_header = merge_uapi_header(merged_manager_header, upstream_header)
    upstream_dispatch = upstream_dispatch_path.read_text()
    merged_dispatch = merge_event_cases(
        upstream_header,
        upstream_dispatch,
        local_dispatch_path.read_text(),
    )
    merged_dispatch = merge_lookup_symbols_dispatch(upstream_dispatch, merged_dispatch)
    merged_dispatch = merge_manager_dispatch(upstream_dispatch, merged_dispatch)

    header_changed = write_if_changed(local_header_path, merged_header)
    dispatch_changed = write_if_changed(local_dispatch_path, merged_dispatch)
    validate_non_event_contract(merged_header, upstream_header)
    version = re.search(
        r"DECLARE\(\s*__u32\s*,\s*KERNEL_SU_UAPI_VERSION\s*,\s*(\d+)\s*\)",
        upstream_header,
    ).group(1)
    events = re.findall(
        r"DECLARE\(\s*__u32\s*,\s*(EVENT_[A-Z0-9_]+)\s*,",
        upstream_header,
    )
    print(
        f"[uapi-sync] SukiSU UAPI {version}: {len(events)} events; "
        f"header {'updated' if header_changed else 'current'}, "
        f"dispatch {'updated' if dispatch_changed else 'current'}."
    )


if __name__ == "__main__":
    main()
