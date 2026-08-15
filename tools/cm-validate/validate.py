#!/usr/bin/env python3
"""Read-only static validation for a CM FiveM repository."""

from __future__ import annotations

import argparse
import glob
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

BLOCK_KEYS = ("client_scripts", "server_scripts", "shared_scripts", "files", "dependencies")
SINGLE_KEYS = ("client_script", "server_script", "shared_script", "file", "dependency", "ui_page")


def lua_without_comments(text: str) -> str:
    return "\n".join(re.sub(r"--.*$", "", line) for line in text.splitlines())


def quoted_values(text: str) -> list[str]:
    return re.findall(r"['\"]([^'\"]+)['\"]", text)


def manifest_values(text: str, key: str) -> list[str]:
    clean = lua_without_comments(text)
    values: list[str] = []
    plural = key if key.endswith("s") else None
    if plural:
        for match in re.finditer(rf"\b{re.escape(plural)}\s*\{{(.*?)\}}", clean, re.S):
            values.extend(quoted_values(match.group(1)))
    single = key[:-1] if key.endswith("s") else key
    for match in re.finditer(rf"\b{re.escape(single)}\s*(?:\(|\s)\s*['\"]([^'\"]+)['\"]", clean):
        values.append(match.group(1))
    return values


def discover_resources(root: Path) -> tuple[dict[str, Path], list[str]]:
    found: dict[str, Path] = {}
    warnings: list[str] = []
    manifests = list((root / "resources").rglob("fxmanifest.lua")) + list((root / "resources").rglob("__resource.lua"))
    # A FiveM resource in this repository is resources/<group>/<resource>.
    # Ignore manifests embedded in vendor build/source subdirectories.
    manifests = [p for p in manifests if len(p.relative_to(root / "resources").parts) == 3]
    for manifest in sorted(manifests, key=lambda p: len(p.parts)):
        name = manifest.parent.name
        if name in found and found[name] != manifest.parent:
            warnings.append(f"duplicate resource name {name}: {found[name]} and {manifest.parent}")
            continue
        found[name] = manifest.parent
    return found, warnings


def active_config_lines(path: Path) -> list[tuple[int, str]]:
    result = []
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = raw.strip()
        if line and not line.startswith("#"):
            result.append((number, line))
    return result


def documented_private_assets(root: Path) -> set[str]:
    path = root / "PRIVATE_ASSETS.md"
    if not path.exists():
        return set()
    return set(re.findall(r"`([A-Za-z0-9_.-]+)`", path.read_text(encoding="utf-8")))


def check_balanced(text: str) -> bool:
    clean = lua_without_comments(text)
    pairs = {"{": "}", "(": ")"}
    stack: list[str] = []
    quote = None
    escaped = False
    for char in clean:
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in "'\"":
            quote = char
        elif char in pairs:
            stack.append(pairs[char])
        elif char in pairs.values():
            if not stack or stack.pop() != char:
                return False
    return not stack and quote is None


def referenced_path_exists(resource: Path, value: str) -> bool:
    if value.startswith("@") or value.startswith("http://") or value.startswith("https://"):
        return True
    candidate = str(resource / value)
    if any(token in value for token in "*?["):
        return bool(glob.glob(candidate, recursive=True))
    return Path(candidate).exists()


def find_cycles(graph: dict[str, list[str]]) -> list[list[str]]:
    cycles: list[list[str]] = []
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> None:
        state[node] = 1
        stack.append(node)
        for dep in graph.get(node, []):
            if dep not in graph:
                continue
            if state.get(dep, 0) == 0:
                visit(dep)
            elif state.get(dep) == 1:
                cycle = stack[stack.index(dep):] + [dep]
                if cycle not in cycles:
                    cycles.append(cycle)
        stack.pop()
        state[node] = 2

    for node in graph:
        if state.get(node, 0) == 0:
            visit(node)
    return cycles


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="repository root")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    errors: list[str] = []
    warnings: list[str] = []

    config = root / "server.cfg"
    if not config.exists():
        print("ERROR: server.cfg is missing")
        return 1

    resources, discovery_warnings = discover_resources(root)
    warnings.extend(discovery_warnings)
    lines = active_config_lines(config)
    ensures = [(n, m.group(1)) for n, line in lines if (m := re.match(r"ensure\s+(\S+)", line, re.I))]
    ensure_names = [name for _, name in ensures]
    ensure_position = {name: index for index, name in enumerate(ensure_names)}
    private = documented_private_assets(root)

    for name, count in Counter(ensure_names).items():
        if count > 1:
            errors.append(f"duplicate active ensure: {name} ({count} times)")
    for line_no, name in ensures:
        if name not in resources:
            message = f"server.cfg:{line_no}: ensured resource not found: {name}"
            (warnings if name in private else errors).append(message)

    cfg_statements = [(n, line) for n, line in lines if re.match(r"add_(ace|principal)\b", line, re.I)]
    for statement, count in Counter(line for _, line in cfg_statements).items():
        if count > 1:
            errors.append(f"duplicate server.cfg statement ({count} times): {statement}")

    dependency_graph: dict[str, list[str]] = defaultdict(list)
    newest_source = config.stat().st_mtime
    for name, directory in resources.items():
        manifest = directory / "fxmanifest.lua"
        if not manifest.exists():
            manifest = directory / "__resource.lua"
        newest_source = max(newest_source, manifest.stat().st_mtime)
        text = manifest.read_text(encoding="utf-8-sig", errors="replace")
        deps = [d for d in manifest_values(text, "dependencies") if not d.startswith("/")]
        dependency_graph[name] = deps
        for dep in deps:
            if name in ensure_position and dep not in resources:
                errors.append(f"{name}: hard dependency not found: {dep}")
            if name in ensure_position and dep in ensure_position and ensure_position[dep] > ensure_position[name]:
                errors.append(f"server.cfg order: {dep} must start before {name}")
        if name in ensure_position:
            refs: list[str] = []
            for key in ("client_scripts", "server_scripts", "shared_scripts", "files"):
                refs.extend(manifest_values(text, key))
            refs.extend(manifest_values(text, "ui_page"))
            for value in dict.fromkeys(refs):
                if not referenced_path_exists(directory, value):
                    message = f"{name}: manifest path not found: {value}"
                    if any(token in value for token in "*?["):
                        continue  # An empty wildcard set is valid in a FiveM manifest.
                    (warnings if name in private else errors).append(message)

    active_graph = {
        name: [dep for dep in dependency_graph.get(name, []) if dep in ensure_position]
        for name in ensure_names if name in resources
    }
    for cycle in find_cycles(active_graph):
        errors.append("hard dependency cycle: " + " -> ".join(cycle))

    for expected in ("README.md", "PRIVATE_ASSETS.md", "server.local.example.cfg"):
        if not (root / expected).exists():
            errors.append(f"missing expected repository file: {expected}")
    registry = root / "agent-docs" / "resource-registry.yaml"
    if not registry.exists():
        warnings.append("agent-docs/resource-registry.yaml is missing")
    elif registry.stat().st_mtime < newest_source:
        warnings.append("agent-docs/resource-registry.yaml may be stale relative to manifests/server.cfg")

    print(f"Resources discovered: {len(resources)}; active ensures: {len(ensure_names)}")
    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    print(f"Validation complete: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
