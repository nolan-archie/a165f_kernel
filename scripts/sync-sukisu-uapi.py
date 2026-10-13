#!/usr/bin/env python3
"""Sync the current SukiSU UAPI and import newly declared event handlers."""

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


def normalized_uapi_contract(header: str) -> str:
    """Ignore comments, formatting, the version, and event IDs for ABI checks."""
    contract = re.sub(r"/\*.*?\*/|//[^\n]*", "", header, flags=re.DOTALL)
    contract = re.sub(
        r"DECLARE\(\s*__u32\s*,\s*KERNEL_SU_UAPI_VERSION\s*,[^;]+;\s*",
        "",
        contract,
    )
    contract = re.sub(
        r"DECLARE\(\s*__u32\s*,\s*EVENT_[A-Z0-9_]+\s*,[^;]+;\s*",
        "",
        contract,
    )
    return re.sub(r"\s+", "", contract)


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
    if normalized_uapi_contract(previous_header) != normalized_uapi_contract(upstream_header):
        fail(
            "upstream changed non-event UAPI definitions; refusing to advertise an "
            "API whose new ioctl or data structure has not been ported"
        )
    merged_dispatch = merge_event_cases(
        upstream_header,
        upstream_dispatch_path.read_text(),
        local_dispatch_path.read_text(),
    )

    header_changed = write_if_changed(local_header_path, upstream_header)
    dispatch_changed = write_if_changed(local_dispatch_path, merged_dispatch)
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
