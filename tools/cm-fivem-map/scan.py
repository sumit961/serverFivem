#!/usr/bin/env python3
"""cm-fivem-map: portable FiveM contract scanner (Phase 1).

Standard-library only. Understands FiveM-specific relationships that a
generic AST tool does not: net/local events, cross-resource exports, NUI
callbacks, ox_lib callbacks, MySQL/oxmysql table usage, commands and ACE
permissions. See tools/cm-fivem-map/README.md for the full picture.
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import re

SCHEMA_VERSION = "1.0.0"
SCANNER_VERSION = "0.1.0"

CODE_EXTS = {".lua", ".js", ".ts"}
SCAN_EXTS = {".lua", ".js", ".ts", ".html", ".sql"}

# ---------------------------------------------------------------------------
# Always-excluded paths (defense in depth, independent of .gitignore/.graphifyignore)
# ---------------------------------------------------------------------------

# Component sequences matched anywhere in the relative path (any depth).
ALWAYS_EXCLUDE_ANYWHERE = {
    ".git", "graphify-out", "cm-agent-out", "cache", "logs",
    "node_modules", "stream", "local-security-backup",
}

# Exact positional prefixes from the repository root (component tuples).
# Bracket names are literal strings here -- no glob/fnmatch involved, so the
# escaping ambiguity that affects Graphify's ignore matcher does not apply.
ALWAYS_EXCLUDE_PREFIXES = [
    ("resources", "[mlo]"),
    ("resources", "[clothes]"),
    ("resources", "[core]", "bcrypt", "dist"),
    ("resources", "[core]", "nv_cloth", "nv_cloth"),
    ("resources", "[system]", "[builders]", "yarn"),
    # this scanner's own source/tests -- not a FiveM game resource
    ("tools",),
]

# Exact relative-path basenames that must never be opened, regardless of
# ignore-file state (defense in depth for secrets).
NEVER_READ_BASENAMES = {"server.local.cfg"}


def _norm_parts(rel: str) -> tuple:
    return tuple(p for p in rel.replace("\\", "/").split("/") if p)


def is_always_excluded(rel: str) -> bool:
    parts = _norm_parts(rel)
    if not parts:
        return False
    if parts[-1] in NEVER_READ_BASENAMES:
        return True
    if any(p in ALWAYS_EXCLUDE_ANYWHERE for p in parts):
        return True
    for prefix in ALWAYS_EXCLUDE_PREFIXES:
        if parts[: len(prefix)] == prefix:
            return True
    return False


# ---------------------------------------------------------------------------
# Ignore-file engine (independent reimplementation, not Graphify's matcher)
# ---------------------------------------------------------------------------
#
# Supports standard gitignore glob semantics *with working backslash escapes*
# (unlike Python's bare fnmatch, which does not honour '\['). This lets the
# same engine correctly read both:
#   .gitignore      -> resources/\[mlo\]/         (git backslash-escape form)
#   .graphifyignore -> resources/[[]mlo[]]/        (fnmatch bracket-class form)
# because a bracket-class containing a single literal '[' or ']' is valid,
# portable POSIX glob syntax understood by both a proper glob engine and by
# fnmatch -- it is only the backslash-escape *form* that fnmatch rejects.


def _translate_glob_segment(pat: str) -> str:
    """Translate one gitignore glob pattern (no leading/trailing slash
    handling) into a regex string. Supports '*', '**', '?', '[...]'/'[!...]'
    classes (with POSIX leading-']' literal quirk), and backslash escapes.
    """
    i, n = 0, len(pat)
    out = []
    while i < n:
        c = pat[i]
        if c == "\\" and i + 1 < n:
            out.append(re.escape(pat[i + 1]))
            i += 2
            continue
        if c == "*":
            if i + 1 < n and pat[i + 1] == "*":
                out.append(".*")
                i += 2
                # swallow an immediately following '/' as part of '**/'
                if i < n and pat[i] == "/":
                    out.append("/?")
                    i += 1
            else:
                out.append("[^/]*")
                i += 1
            continue
        if c == "?":
            out.append("[^/]")
            i += 1
            continue
        if c == "[":
            j = i + 1
            neg = False
            if j < n and pat[j] in "!^":
                neg = True
                j += 1
            first = j
            if j < n and pat[j] == "]":
                j += 1
            while j < n and pat[j] != "]":
                j += 1
            if j >= n:
                out.append(re.escape("["))
                i += 1
                continue
            body = pat[first:j]
            # Escape backslash and literal '[' inside the class body: '[' is
            # not special to POSIX bracket expressions, but recent Python
            # warns ("possible nested set") when it appears unescaped inside
            # a re character class, since a future syntax may reserve it.
            body = body.replace("\\", "\\\\").replace("[", "\\[")
            out.append("[" + ("^" if neg else "") + body + "]")
            i = j + 1
            continue
        out.append(re.escape(c))
        i += 1
    return "".join(out)


@dataclass
class IgnoreRule:
    anchored: bool
    negated: bool
    regex: re.Pattern


def _parse_ignore_line(raw: str) -> Optional[str]:
    line = raw.rstrip("\n\r")
    line = line.lstrip(" \t")
    if not line or line.startswith("#"):
        return None
    line = re.sub(r"(?<!\\)\s+$", "", line)
    return line if line else None


def _compile_ignore_rule(line: str) -> IgnoreRule:
    negated = line.startswith("!")
    if negated:
        line = line[1:]
    anchored = line.startswith("/")
    line = line.strip("/")
    body = _translate_glob_segment(line)
    regex = re.compile("^" + body + "$")
    return IgnoreRule(anchored=anchored, negated=negated, regex=regex)


class IgnoreMatcher:
    """Honours .gitignore and .graphifyignore, last-match-wins, plus the
    hardcoded always-exclude list. Independent of Graphify's own matcher."""

    def __init__(self, root: Path):
        self.root = root
        self.rules: list[IgnoreRule] = []
        for name in (".gitignore", ".graphifyignore"):
            p = root / name
            if p.is_file():
                try:
                    text = p.read_text(encoding="utf-8", errors="ignore")
                except OSError:
                    continue
                for raw in text.splitlines():
                    line = _parse_ignore_line(raw)
                    if line:
                        self.rules.append(_compile_ignore_rule(line))

    def is_ignored(self, rel: str) -> bool:
        rel = rel.replace("\\", "/").strip("/")
        if not rel:
            return False
        if is_always_excluded(rel):
            return True
        parts = rel.split("/")
        result = False
        for rule in self.rules:
            matched = False
            if rule.anchored:
                matched = bool(rule.regex.match(rel))
            else:
                if rule.regex.match(rel):
                    matched = True
                else:
                    for k in range(len(parts)):
                        if rule.regex.match(parts[k]) or rule.regex.match("/".join(parts[: k + 1])):
                            matched = True
                            break
            if matched:
                result = not rule.negated
        return result


# ---------------------------------------------------------------------------
# Deterministic IDs
# ---------------------------------------------------------------------------


def make_id(kind: str, *parts: object) -> str:
    joined = "::".join(str(p) for p in parts)
    digest = hashlib.sha1(joined.encode("utf-8")).hexdigest()[:12]
    return f"{kind}_{digest}"


# ---------------------------------------------------------------------------
# Lexical tokenizer (comment/string masking, line-accurate)
# ---------------------------------------------------------------------------


@dataclass
class Token:
    kind: str  # 'code' | 'comment' | 'string'
    value: Optional[str]  # decoded literal value for 'string' tokens (None if dynamic/interp)
    start: int
    end: int
    line: int


def _match_long_bracket_open(text: str, i: int) -> Optional[tuple]:
    n = len(text)
    if i >= n or text[i] != "[":
        return None
    j = i + 1
    eq = 0
    while j < n and text[j] == "=":
        eq += 1
        j += 1
    if j < n and text[j] == "[":
        return (j + 1, eq)
    return None


def tokenize_lua(text: str) -> list[Token]:
    tokens: list[Token] = []
    i, n = 0, len(text)
    line = 1
    code_start, code_start_line = 0, 1

    def flush_code(end: int) -> None:
        nonlocal code_start, code_start_line
        if end > code_start:
            tokens.append(Token("code", text[code_start:end], code_start, end, code_start_line))
        code_start = end

    while i < n:
        c = text[i]
        if c == "-" and i + 1 < n and text[i + 1] == "-":
            flush_code(i)
            start, start_line = i, line
            i += 2
            m = _match_long_bracket_open(text, i)
            if m is not None:
                content_start, eq = m
                closer = "]" + "=" * eq + "]"
                end_idx = text.find(closer, content_start)
                i = n if end_idx == -1 else end_idx + len(closer)
            else:
                j = text.find("\n", i)
                i = n if j == -1 else j
            raw = text[start:i]
            line += raw.count("\n")
            tokens.append(Token("comment", None, start, i, start_line))
            code_start, code_start_line = i, line
            continue
        if c == "[":
            m = _match_long_bracket_open(text, i)
            if m is not None:
                flush_code(i)
                start, start_line = i, line
                content_start, eq = m
                closer = "]" + "=" * eq + "]"
                end_idx = text.find(closer, content_start)
                if end_idx == -1:
                    value = text[content_start:n]
                    i = n
                else:
                    value = text[content_start:end_idx]
                    i = end_idx + len(closer)
                raw = text[start:i]
                line += raw.count("\n")
                tokens.append(Token("string", value, start, i, start_line))
                code_start, code_start_line = i, line
                continue
        if c in ("'", '"'):
            flush_code(i)
            start, start_line = i, line
            quote = c
            j = i + 1
            buf = []
            while j < n:
                cj = text[j]
                if cj == "\\" and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                    continue
                if cj == quote:
                    j += 1
                    break
                if cj == "\n":
                    break
                buf.append(cj)
                j += 1
            raw = text[start:j]
            tokens.append(Token("string", "".join(buf), start, j, start_line))
            line += raw.count("\n")
            i = j
            code_start, code_start_line = i, line
            continue
        if c == "\n":
            line += 1
        i += 1
    flush_code(n)
    return tokens


def tokenize_js(text: str) -> list[Token]:
    tokens: list[Token] = []
    i, n = 0, len(text)
    line = 1
    code_start, code_start_line = 0, 1

    def flush_code(end: int) -> None:
        nonlocal code_start, code_start_line
        if end > code_start:
            tokens.append(Token("code", text[code_start:end], code_start, end, code_start_line))
        code_start = end

    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            flush_code(i)
            start, start_line = i, line
            j = text.find("\n", i)
            i = n if j == -1 else j
            tokens.append(Token("comment", None, start, i, start_line))
            code_start, code_start_line = i, line
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            flush_code(i)
            start, start_line = i, line
            j = text.find("*/", i + 2)
            i = n if j == -1 else j + 2
            raw = text[start:i]
            line += raw.count("\n")
            tokens.append(Token("comment", None, start, i, start_line))
            code_start, code_start_line = i, line
            continue
        if c in ("'", '"', "`"):
            flush_code(i)
            start, start_line = i, line
            quote = c
            j = i + 1
            buf = []
            dynamic = False
            while j < n:
                cj = text[j]
                if cj == "\\" and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                    continue
                if quote == "`" and cj == "$" and j + 1 < n and text[j + 1] == "{":
                    dynamic = True
                    depth = 1
                    j += 2
                    while j < n and depth > 0:
                        if text[j] == "{":
                            depth += 1
                        elif text[j] == "}":
                            depth -= 1
                        j += 1
                    continue
                if cj == quote:
                    j += 1
                    break
                if cj == "\n" and quote != "`":
                    break
                buf.append(cj)
                j += 1
            raw = text[start:j]
            value = None if dynamic else "".join(buf)
            tokens.append(Token("string", value, start, j, start_line))
            line += raw.count("\n")
            i = j
            code_start, code_start_line = i, line
            continue
        if c == "\n":
            line += 1
        i += 1
    flush_code(n)
    return tokens


SCRIPT_BLOCK_RE = re.compile(r"<script\b[^>]*>(.*?)</script>", re.IGNORECASE | re.DOTALL)


def tokenize_html(text: str) -> list[Token]:
    """Extract <script> blocks and tokenize their contents as JS, preserving
    absolute file offsets/line numbers. Non-script regions are treated as a
    single opaque 'code' token (we do not attempt HTML comment stripping;
    our patterns only fire inside script blocks)."""
    tokens: list[Token] = []
    pos = 0
    for m in SCRIPT_BLOCK_RE.finditer(text):
        block_start, block_end = m.start(1), m.end(1)
        if block_start > pos:
            tokens.append(Token("code", text[pos:block_start], pos, block_start, 1))
        block_text = text[block_start:block_end]
        offset_line = text.count("\n", 0, block_start) + 1
        for t in tokenize_js(block_text):
            tokens.append(
                Token(
                    t.kind,
                    t.value,
                    t.start + block_start,
                    t.end + block_start,
                    t.line + offset_line - 1,
                )
            )
        pos = block_end
    if pos < len(text):
        tokens.append(Token("code", text[pos:], pos, len(text), 1))
    return tokens


def build_masked(text: str, tokens: list[Token]) -> str:
    chars = list(text)
    for t in tokens:
        if t.kind in ("comment", "string"):
            for idx in range(t.start, t.end):
                if chars[idx] != "\n":
                    chars[idx] = " "
    return "".join(chars)


class LineIndex:
    def __init__(self, text: str):
        self.starts = [0]
        for idx, ch in enumerate(text):
            if ch == "\n":
                self.starts.append(idx + 1)

    def line_at(self, pos: int) -> int:
        return bisect.bisect_right(self.starts, pos)


class TokenIndex:
    """Fast lookup of 'the next meaningful token at/after position P'."""

    def __init__(self, tokens: list[Token]):
        self.tokens = tokens
        self.starts = [t.start for t in tokens]

    def next_literal_after(self, pos: int, max_lookahead: int = 600):
        idx = bisect.bisect_left(self.starts, pos)
        # a token may already be open at pos (start < pos < end)
        if idx > 0 and self.tokens[idx - 1].end > pos:
            idx -= 1
        for t in self.tokens[idx:]:
            if t.end <= pos:
                continue
            if t.start - pos > max_lookahead:
                return None, "too_far"
            if t.kind == "comment":
                continue
            if t.kind == "code":
                # Only the portion of this token from `pos` onward is
                # relevant -- a code token may start before `pos` (e.g. it
                # also contains the call keyword itself), and text before
                # `pos` must not count as "code before the literal".
                visible_start = max(t.start, pos)
                stripped = t.value[visible_start - t.start :].strip() if t.value else ""
                if stripped == "":
                    continue
                return None, "non_literal"
            if t.kind == "string":
                if t.value is None:
                    return None, "dynamic_interpolation"
                return t, "literal"
        return None, "eof"


# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------


@dataclass
class Contract:
    id: str
    type: str
    name: str
    resource: Optional[str]
    target_resource: Optional[str]
    file: str
    line: int
    context: str
    operation: str
    confidence: str  # 'EXTRACTED' | 'INFERRED'
    syntax: str
    dynamic_name: bool
    unresolved_reason: Optional[str] = None
    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        d = {
            "id": self.id,
            "type": self.type,
            "name": self.name,
            "resource": self.resource,
            "target_resource": self.target_resource,
            "file": self.file,
            "line": self.line,
            "context": self.context,
            "operation": self.operation,
            "confidence": self.confidence,
            "syntax": self.syntax,
            "dynamic_name": self.dynamic_name,
            "unresolved_reason": self.unresolved_reason,
        }
        d.update(self.extra)
        return d


def infer_context(relpath: str) -> str:
    parts = [p.lower() for p in relpath.replace("\\", "/").split("/")]
    fname = parts[-1] if parts else ""
    ext = Path(fname).suffix
    is_nui_like = ext in (".html", ".js", ".ts")
    if "client" in parts or fname.startswith("cl_") or fname == "client.lua":
        return "client"
    if "server" in parts or fname.startswith("sv_") or fname == "server.lua":
        return "server"
    if is_nui_like and any(p in ("html", "ui", "nui", "web") for p in parts):
        return "nui"
    if is_nui_like:
        return "nui"
    if "shared" in parts or fname.startswith("sh_") or fname in ("shared.lua", "config.lua"):
        return "shared"
    if fname in ("fxmanifest.lua", "__resource.lua"):
        return "shared"
    return "unknown"


# ---------------------------------------------------------------------------
# Resource discovery
# ---------------------------------------------------------------------------


@dataclass
class Resource:
    id: str
    name: str
    path: str  # repo-relative
    owner_collection: Optional[str]
    manifest_path: str
    manifest_kind: str  # 'fxmanifest.lua' | '__resource.lua'
    nested_manifest_candidate: bool


def is_bracket_collection(name: str) -> bool:
    return bool(re.match(r"^\[.+\]$", name))


def discover_resources(root: Path, ignore: IgnoreMatcher, verbose: bool = False) -> list[Resource]:
    resources: list[Resource] = []
    manifest_dirs: list[Path] = []
    for dirpath, dirnames, filenames in _walk(root, ignore):
        if "fxmanifest.lua" in filenames or "__resource.lua" in filenames:
            manifest_dirs.append(dirpath)
    manifest_dirs.sort(key=lambda p: str(p).lower())

    manifest_dir_set = set(manifest_dirs)
    for d in manifest_dirs:
        rel = d.relative_to(root).as_posix()
        parts = rel.split("/") if rel != "." else []
        if parts and is_bracket_collection(parts[-1]):
            continue
        name = d.name
        owner = None
        if len(parts) >= 2 and is_bracket_collection(parts[-2]):
            owner = parts[-2]
        manifest_kind = "fxmanifest.lua" if (d / "fxmanifest.lua").exists() else "__resource.lua"
        nested = any(
            other != d and other in d.parents for other in manifest_dir_set
        )
        resources.append(
            Resource(
                id=make_id("res", rel),
                name=name,
                path=rel,
                owner_collection=owner,
                manifest_path=f"{rel}/{manifest_kind}",
                manifest_kind=manifest_kind,
                nested_manifest_candidate=nested,
            )
        )
    resources.sort(key=lambda r: r.path.lower())
    return resources


def _walk(root: Path, ignore: IgnoreMatcher):
    """os.walk-style traversal honouring the ignore matcher, pruning ignored
    directories so we never descend into them."""
    import os

    for dirpath, dirnames, filenames in os.walk(root):
        dp = Path(dirpath)
        rel = dp.relative_to(root).as_posix() if dp != root else ""
        keep = []
        for d in dirnames:
            child_rel = f"{rel}/{d}" if rel else d
            if not ignore.is_ignored(child_rel):
                keep.append(d)
        dirnames[:] = keep
        yield dp, dirnames, filenames


def resource_for_path(rel: str, resources: list[Resource]) -> Optional[Resource]:
    best = None
    for r in resources:
        if rel == r.path or rel.startswith(r.path + "/"):
            if best is None or len(r.path) > len(best.path):
                best = r
    return best


# ---------------------------------------------------------------------------
# File model
# ---------------------------------------------------------------------------


@dataclass
class ScannedFile:
    rel: str
    resource: Optional[Resource]
    context: str
    text: str
    tokens: list[Token]
    masked: str
    lines: LineIndex
    tokidx: TokenIndex
    local_string_vars: dict


def load_file(root: Path, rel: str, resources: list[Resource], diagnostics: dict) -> Optional[ScannedFile]:
    parts = _norm_parts(rel)
    if parts and parts[-1] in NEVER_READ_BASENAMES:
        return None
    p = root / rel
    ext = p.suffix.lower()
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        diagnostics["errors"].append({"file": rel, "error": f"read_error: {exc.__class__.__name__}"})
        return None
    try:
        if ext in (".lua",):
            tokens = tokenize_lua(text)
        elif ext in (".js", ".ts"):
            tokens = tokenize_js(text)
        elif ext == ".html":
            tokens = tokenize_html(text)
        elif ext == ".sql":
            tokens = [Token("code", text, 0, len(text), 1)]
        else:
            tokens = [Token("code", text, 0, len(text), 1)]
    except Exception as exc:  # pragma: no cover - defensive
        diagnostics["errors"].append({"file": rel, "error": f"parse_error: {exc.__class__.__name__}"})
        return None
    masked = build_masked(text, tokens)
    res = resource_for_path(rel, resources)
    ctx = infer_context(rel)
    sf = ScannedFile(
        rel=rel,
        resource=res,
        context=ctx,
        text=text,
        tokens=tokens,
        masked=masked,
        lines=LineIndex(text),
        tokidx=TokenIndex(tokens),
        local_string_vars={},
    )
    if ext in (".lua", ".js", ".ts"):
        sf.local_string_vars = _extract_local_string_vars(sf)
    return sf


# No trailing '\s*' after '=': masked-out string regions are spaces too, so a
# greedy trailing '\s*' would consume straight through an entire masked
# string literal before token lookup even starts. Stop right after '=' and
# let next_literal_after() walk token boundaries instead.
ASSIGN_RE = re.compile(r"\b(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)")


def _extract_local_string_vars(sf: ScannedFile) -> dict:
    out: dict = {}
    for m in ASSIGN_RE.finditer(sf.masked):
        name = m.group(1)
        tok, status = sf.tokidx.next_literal_after(m.end(), max_lookahead=8)
        if status == "literal" and tok.value is not None:
            out[name] = tok.value
    return out


CONCAT_FOLLOW_RE = re.compile(r"^\s*(\.\.|\+)(?!\))")


def resolve_arg_value(sf: ScannedFile, after_pos: int) -> tuple[Optional[str], bool, Optional[str]]:
    """Returns (value, dynamic, unresolved_reason) for the token immediately
    following a call's opening paren, resolving simple same-file local
    string-variable references. A literal immediately followed by a Lua '..'
    or JS '+' concatenation operator is NOT a complete literal -- the real
    runtime value depends on a variable, so it is reported dynamic/unresolved
    rather than silently truncated to its static prefix."""
    tok, status = sf.tokidx.next_literal_after(after_pos)
    if status == "literal":
        if CONCAT_FOLLOW_RE.match(sf.masked[tok.end : tok.end + 8]):
            return None, True, "string_concatenation"
        return tok.value, False, None
    if status == "non_literal":
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,)]", sf.masked[after_pos : after_pos + 200])
        if m and m.group(1) in sf.local_string_vars:
            return sf.local_string_vars[m.group(1)], False, None
        return None, True, "non_literal_argument"
    if status == "dynamic_interpolation":
        return None, True, "template_interpolation"
    if status == "too_far":
        return None, True, "argument_too_far"
    return None, True, "no_argument_found"


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

EVENT_REGISTER_PATTERNS = [
    ("register_net_event", re.compile(r"\bRegisterNetEvent\s*\(")),
    ("register_server_event", re.compile(r"\bRegisterServerEvent\s*\(")),
    ("add_event_handler", re.compile(r"\bAddEventHandler\s*\(")),
]

EVENT_TRIGGER_PATTERNS = [
    ("trigger_server_event", re.compile(r"\bTriggerServerEvent\s*\(")),
    ("trigger_client_event", re.compile(r"\bTriggerClientEvent\s*\(")),
    ("trigger_latent_server_event", re.compile(r"\bTriggerLatentServerEvent\s*\(")),
    ("trigger_latent_client_event", re.compile(r"\bTriggerLatentClientEvent\s*\(")),
    ("trigger_event", re.compile(r"\bTriggerEvent\s*\(")),
]


def scan_events(sf: ScannedFile, diagnostics: dict) -> list[Contract]:
    out: list[Contract] = []
    resource_name = sf.resource.name if sf.resource else None
    for op, pat in EVENT_REGISTER_PATTERNS:
        for m in pat.finditer(sf.masked):
            line = sf.lines.line_at(m.start())
            value, dynamic, reason = resolve_arg_value(sf, m.end())
            name = value if value is not None else "<dynamic>"
            out.append(
                Contract(
                    id=make_id("evtreg", sf.rel, line, op, name),
                    type="event_registration",
                    name=name,
                    resource=resource_name,
                    target_resource=None,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation=op,
                    confidence="EXTRACTED" if not dynamic else "INFERRED",
                    syntax=op,
                    dynamic_name=dynamic,
                    unresolved_reason=reason,
                )
            )
    for op, pat in EVENT_TRIGGER_PATTERNS:
        for m in pat.finditer(sf.masked):
            line = sf.lines.line_at(m.start())
            value, dynamic, reason = resolve_arg_value(sf, m.end())
            name = value if value is not None else "<dynamic>"
            out.append(
                Contract(
                    id=make_id("evttrig", sf.rel, line, op, name),
                    type="event_trigger",
                    name=name,
                    resource=resource_name,
                    target_resource=None,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation=op,
                    confidence="EXTRACTED" if not dynamic else "INFERRED",
                    syntax=op,
                    dynamic_name=dynamic,
                    unresolved_reason=reason,
                )
            )
    return out


TRIGGER_TO_HANDLER_DIRECTION = {
    "trigger_server_event": "client_to_server",
    "trigger_latent_server_event": "client_to_server",
    "trigger_client_event": "server_to_client",
    "trigger_latent_client_event": "server_to_client",
    "trigger_event": "local",
}


def build_event_relationships(events: list[Contract]) -> list[dict]:
    # RegisterNetEvent/RegisterServerEvent are declarations, not handlers --
    # AddEventHandler is what actually attaches a callback. Counting the
    # declaration too would double-count the idiomatic
    # RegisterNetEvent(name); AddEventHandler(name, fn) pair as "2 handlers".
    handlers = [c for c in events if c.type == "event_registration" and c.operation == "add_event_handler"]
    triggers = [c for c in events if c.type == "event_trigger"]

    handlers_by_name: dict[str, list[Contract]] = {}
    for h in handlers:
        if h.dynamic_name:
            continue
        handlers_by_name.setdefault(h.name, []).append(h)

    relationships: list[dict] = []
    triggered_names: set[str] = set()

    for t in triggers:
        direction = TRIGGER_TO_HANDLER_DIRECTION.get(t.operation, "unknown")
        rel = {
            "id": make_id("evtrel", t.file, t.line, t.operation, t.name),
            "event": t.name,
            "direction": direction,
            "dynamic_name": t.dynamic_name,
            "trigger": {"resource": t.resource, "file": t.file, "line": t.line, "operation": t.operation},
            "handlers": [],
            "handler_count": 0,
            "status": "unresolved",
        }
        if t.dynamic_name:
            rel["status"] = "dynamic_unresolved"
            relationships.append(rel)
            continue
        triggered_names.add(t.name)
        candidates = handlers_by_name.get(t.name, [])
        if direction == "client_to_server":
            candidates = [h for h in candidates if h.context != "client"]
        elif direction == "server_to_client":
            candidates = [h for h in candidates if h.context != "server"]
        rel["handlers"] = [
            {"resource": h.resource, "file": h.file, "line": h.line, "context": h.context, "operation": h.operation}
            for h in candidates
        ]
        rel["handler_count"] = len(candidates)
        if len(candidates) == 0:
            rel["status"] = "unresolved_no_handler"
        elif len(candidates) == 1:
            rel["status"] = "resolved"
        else:
            rel["status"] = "resolved_multiple"
        if direction == "client_to_server" and any(h.context == "client" for h in handlers_by_name.get(t.name, [])):
            rel["direction_mismatch_note"] = "handler(s) also registered client-side"
        if direction == "server_to_client" and any(h.context == "server" for h in handlers_by_name.get(t.name, [])):
            rel["direction_mismatch_note"] = "handler(s) also registered server-side"
        relationships.append(rel)

    for name, hs in handlers_by_name.items():
        if name not in triggered_names:
            for h in hs:
                relationships.append(
                    {
                        "id": make_id("evtrel_untrig", h.file, h.line, name),
                        "event": name,
                        "direction": "unknown",
                        "dynamic_name": False,
                        "trigger": None,
                        "handlers": [
                            {"resource": h.resource, "file": h.file, "line": h.line, "context": h.context, "operation": h.operation}
                        ],
                        "handler_count": 1,
                        "status": "untriggered_handler",
                    }
                )
    relationships.sort(key=lambda r: (r["event"], r["status"], r["trigger"]["file"] if r["trigger"] else "", r["trigger"]["line"] if r["trigger"] else 0))
    return relationships


# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

EXPORT_DEF_CALL_RE = re.compile(r"\bexports\s*\(")
EXPORT_DEF_DOT_ASSIGN_RE = re.compile(r"\bexports\.([A-Za-z_][A-Za-z0-9_]*)\s*=")
EXPORT_CONSUMER_DOT_RE = re.compile(r"\bexports\.([A-Za-z_][A-Za-z0-9_]*):([A-Za-z_][A-Za-z0-9_]*)\s*\(")
EXPORT_CONSUMER_BRACKET_RE = re.compile(r"\bexports\[")
MANIFEST_EXPORTS_RE = re.compile(r"\b(server_exports|exports)\s*\{")
MANIFEST_EXPORT_BARE_RE = re.compile(r"\b(server_export|export)\s+")


def scan_exports(sf: ScannedFile, diagnostics: dict) -> list[Contract]:
    out: list[Contract] = []
    resource_name = sf.resource.name if sf.resource else None
    is_manifest = sf.rel.endswith("fxmanifest.lua") or sf.rel.endswith("__resource.lua")

    for m in EXPORT_DEF_CALL_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        value, dynamic, reason = resolve_arg_value(sf, m.end())
        name = value if value is not None else "<dynamic>"
        out.append(
            Contract(
                id=make_id("expdef", sf.rel, line, name),
                type="export_definition",
                name=name,
                resource=resource_name,
                target_resource=None,
                file=sf.rel,
                line=line,
                context=sf.context,
                operation="exports_call",
                confidence="EXTRACTED" if not dynamic else "INFERRED",
                syntax="exports_call",
                dynamic_name=dynamic,
                unresolved_reason=reason,
            )
        )
    for m in EXPORT_DEF_DOT_ASSIGN_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        name = m.group(1)
        out.append(
            Contract(
                id=make_id("expdef", sf.rel, line, name),
                type="export_definition",
                name=name,
                resource=resource_name,
                target_resource=None,
                file=sf.rel,
                line=line,
                context=sf.context,
                operation="exports_dot_assign",
                confidence="EXTRACTED",
                syntax="exports_dot_assign",
                dynamic_name=False,
            )
        )
    if is_manifest:
        for m in MANIFEST_EXPORTS_RE.finditer(sf.text):
            keyword = m.group(1)
            close = sf.text.find("}", m.end())
            body = sf.text[m.end() : close] if close != -1 else sf.text[m.end() : m.end() + 400]
            for sm in re.finditer(r"""(['"])((?:(?!\1).)*)\1""", body):
                line = sf.lines.line_at(m.start())
                name = sm.group(2)
                out.append(
                    Contract(
                        id=make_id("expdef", sf.rel, line, name, keyword),
                        type="export_definition",
                        name=name,
                        resource=resource_name,
                        target_resource=None,
                        file=sf.rel,
                        line=line,
                        context="shared",
                        operation=f"manifest_{keyword}",
                        confidence="EXTRACTED",
                        syntax=f"manifest_{keyword}_table",
                        dynamic_name=False,
                    )
                )

    for m in EXPORT_CONSUMER_DOT_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        target, fname = m.group(1), m.group(2)
        out.append(
            Contract(
                id=make_id("expuse", sf.rel, line, target, fname),
                type="export_consumer",
                name=fname,
                resource=resource_name,
                target_resource=target,
                file=sf.rel,
                line=line,
                context=sf.context,
                operation="exports_dot",
                confidence="EXTRACTED",
                syntax="exports.resource:fn()",
                dynamic_name=False,
            )
        )
    for m in EXPORT_CONSUMER_BRACKET_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        target_tok, status = sf.tokidx.next_literal_after(m.end(), max_lookahead=120)
        rest = sf.masked[m.end() : m.end() + 200]
        # Real FiveM code uses both exports['res']:Fn() (colon call) and
        # exports['res'].Fn() (dot property access called as a function) --
        # both are valid; only the separator differs.
        fname_m = re.search(r"\]\s*[:.]\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(", rest)
        fname = fname_m.group(1) if fname_m else "<unknown>"
        if status == "literal" and target_tok.value is not None:
            out.append(
                Contract(
                    id=make_id("expuse", sf.rel, line, target_tok.value, fname),
                    type="export_consumer",
                    name=fname,
                    resource=resource_name,
                    target_resource=target_tok.value,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation="exports_bracket_string",
                    confidence="EXTRACTED",
                    syntax="exports['resource']:fn()",
                    dynamic_name=False,
                )
            )
        else:
            out.append(
                Contract(
                    id=make_id("expuse", sf.rel, line, "dynamic", fname),
                    type="export_consumer",
                    name=fname,
                    resource=resource_name,
                    target_resource=None,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation="exports_bracket_dynamic",
                    confidence="INFERRED",
                    syntax="exports[var]:fn()",
                    dynamic_name=True,
                    unresolved_reason="dynamic_resource_name",
                )
            )
    return out


def build_export_relationships(exports: list[Contract]) -> list[dict]:
    defs = [c for c in exports if c.type == "export_definition"]
    uses = [c for c in exports if c.type == "export_consumer"]
    defs_by_resource_name: dict[tuple, list[Contract]] = {}
    for d in defs:
        if d.dynamic_name:
            continue
        defs_by_resource_name.setdefault((d.resource, d.name), []).append(d)

    relationships = []
    for u in uses:
        rel = {
            "id": make_id("exprel", u.file, u.line, u.target_resource, u.name),
            "export": u.name,
            "consumer": {"resource": u.resource, "file": u.file, "line": u.line, "context": u.context},
            "target_resource": u.target_resource,
            "definitions": [],
            "status": "unresolved",
        }
        if u.dynamic_name or u.target_resource is None:
            rel["status"] = "dynamic_target_unresolved"
            relationships.append(rel)
            continue
        candidates = defs_by_resource_name.get((u.target_resource, u.name), [])
        rel["definitions"] = [
            {"file": d.file, "line": d.line, "context": d.context} for d in candidates
        ]
        if not candidates:
            has_resource = any(d.resource == u.target_resource for d in defs)
            rel["status"] = "missing_export_definition" if has_resource else "missing_target_resource"
        elif len(candidates) == 1:
            rel["status"] = "resolved"
            if candidates[0].context == "client" and u.context == "server":
                rel["status"] = "resolved_context_mismatch"
            elif candidates[0].context == "server" and u.context == "client":
                rel["status"] = "resolved_context_mismatch"
        else:
            rel["status"] = "resolved_multiple_definitions"
        relationships.append(rel)
    relationships.sort(key=lambda r: (r["export"], str(r["target_resource"]), r["consumer"]["file"], r["consumer"]["line"]))
    return relationships


# ---------------------------------------------------------------------------
# NUI
# ---------------------------------------------------------------------------

NUI_REGISTER_RE = re.compile(r"\bRegisterNUICallback\s*\(")
NUI_REGISTER_TYPE_RE = re.compile(r"\bRegisterNuiCallbackType\s*\(")
NUI_SEND_MESSAGE_RE = re.compile(r"\bSendNUIMessage\s*\(")
NUI_FETCH_RE = re.compile(r"\bfetch\s*\(")


def scan_nui_lua(sf: ScannedFile, diagnostics: dict) -> list[Contract]:
    out: list[Contract] = []
    resource_name = sf.resource.name if sf.resource else None
    for pat, op, syn in (
        (NUI_REGISTER_RE, "register_nui_callback", "RegisterNUICallback"),
        (NUI_REGISTER_TYPE_RE, "register_nui_callback_type", "RegisterNuiCallbackType"),
    ):
        for m in pat.finditer(sf.masked):
            line = sf.lines.line_at(m.start())
            value, dynamic, reason = resolve_arg_value(sf, m.end())
            name = value if value is not None else "<dynamic>"
            out.append(
                Contract(
                    id=make_id("nuireg", sf.rel, line, name),
                    type="nui_registration",
                    name=name,
                    resource=resource_name,
                    target_resource=None,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation=op,
                    confidence="EXTRACTED" if not dynamic else "INFERRED",
                    syntax=syn,
                    dynamic_name=dynamic,
                    unresolved_reason=reason,
                )
            )
    for m in NUI_SEND_MESSAGE_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        out.append(
            Contract(
                id=make_id("nuisend", sf.rel, line),
                type="nui_registration",
                name="<message>",
                resource=resource_name,
                target_resource=None,
                file=sf.rel,
                line=line,
                context=sf.context,
                operation="send_nui_message",
                confidence="EXTRACTED",
                syntax="SendNUIMessage",
                dynamic_name=True,
                unresolved_reason="payload_not_a_callback_name",
            )
        )
    return out


NUI_FETCH_TEMPLATE_RE = re.compile(r"https?://\$\{[^}]*\}/([A-Za-z0-9_\-/]+)")
NUI_FETCH_LITERAL_RE = re.compile(r"https?://([A-Za-z0-9_\-]+)/([A-Za-z0-9_\-/]+)")


def scan_nui_browser(sf: ScannedFile, diagnostics: dict) -> list[Contract]:
    out: list[Contract] = []
    resource_name = sf.resource.name if sf.resource else None
    for m in NUI_FETCH_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        tok, status = sf.tokidx.next_literal_after(m.end(), max_lookahead=300)
        if status == "literal" and tok.value:
            lit_m = NUI_FETCH_LITERAL_RE.search(tok.value)
            if lit_m:
                out.append(
                    Contract(
                        id=make_id("nuicall", sf.rel, line, lit_m.group(2)),
                        type="nui_browser_call",
                        name=lit_m.group(2),
                        resource=resource_name,
                        target_resource=lit_m.group(1) if lit_m.group(1) != resource_name else resource_name,
                        file=sf.rel,
                        line=line,
                        context="nui",
                        operation="fetch_literal_url",
                        confidence="EXTRACTED",
                        syntax="fetch('https://resource/name')",
                        dynamic_name=False,
                    )
                )
                continue
        elif status == "dynamic_interpolation":
            # find the raw token text to recover GetParentResourceName()/... template
            raw = sf.text[m.end() : m.end() + 300]
            tmpl_m = NUI_FETCH_TEMPLATE_RE.search(raw)
            if tmpl_m:
                out.append(
                    Contract(
                        id=make_id("nuicall", sf.rel, line, tmpl_m.group(1)),
                        type="nui_browser_call",
                        name=tmpl_m.group(1),
                        resource=resource_name,
                        target_resource=resource_name,
                        file=sf.rel,
                        line=line,
                        context="nui",
                        operation="fetch_template_parent_resource",
                        confidence="EXTRACTED",
                        syntax="fetch(`https://${GetParentResourceName()}/name`)",
                        dynamic_name=False,
                    )
                )
                continue
        out.append(
            Contract(
                id=make_id("nuicall", sf.rel, line, "dynamic"),
                type="nui_browser_call",
                name="<dynamic>",
                resource=resource_name,
                target_resource=resource_name,
                file=sf.rel,
                line=line,
                context="nui",
                operation="fetch_dynamic",
                confidence="INFERRED",
                syntax="fetch(dynamic)",
                dynamic_name=True,
                unresolved_reason="non_literal_fetch_url",
            )
        )
    return out


def build_nui_relationships(nui: list[Contract]) -> list[dict]:
    regs = [c for c in nui if c.type == "nui_registration" and c.operation.startswith("register_nui_callback")]
    calls = [c for c in nui if c.type == "nui_browser_call"]
    regs_by_resource_name: dict[tuple, list[Contract]] = {}
    for r in regs:
        if r.dynamic_name:
            continue
        regs_by_resource_name.setdefault((r.resource, r.name), []).append(r)

    relationships = []
    matched_reg_ids = set()
    for c in calls:
        rel = {
            "id": make_id("nuirel", c.file, c.line, c.name),
            "callback": c.name,
            "browser_call": {"resource": c.resource, "file": c.file, "line": c.line},
            "target_resource": c.target_resource,
            "handlers": [],
            "status": "unresolved",
        }
        if c.dynamic_name:
            rel["status"] = "dynamic_unresolved"
            relationships.append(rel)
            continue
        candidates = regs_by_resource_name.get((c.target_resource, c.name), [])
        rel["handlers"] = [{"file": r.file, "line": r.line} for r in candidates]
        for r in candidates:
            matched_reg_ids.add(r.id)
        if not candidates:
            rel["status"] = "missing_lua_handler"
        elif len(candidates) == 1:
            rel["status"] = "resolved"
        else:
            rel["status"] = "resolved_multiple"
        relationships.append(rel)

    for r in regs:
        if r.id not in matched_reg_ids and not r.dynamic_name:
            relationships.append(
                {
                    "id": make_id("nuirel_orphan", r.file, r.line, r.name),
                    "callback": r.name,
                    "browser_call": None,
                    "target_resource": r.resource,
                    "handlers": [{"file": r.file, "line": r.line}],
                    "status": "no_detected_browser_caller",
                }
            )
    relationships.sort(key=lambda r: (r["callback"], r["status"]))
    return relationships


# ---------------------------------------------------------------------------
# ox_lib callbacks
# ---------------------------------------------------------------------------

OX_REGISTER_RE = re.compile(r"\blib\.callback\.register\s*\(")
OX_AWAIT_RE = re.compile(r"\blib\.callback\.await\s*\(")
OX_CALL_RE = re.compile(r"\blib\.callback\s*\(")


def scan_ox_callbacks(sf: ScannedFile, diagnostics: dict) -> list[Contract]:
    out: list[Contract] = []
    resource_name = sf.resource.name if sf.resource else None
    for pat, ctype, op, syn in (
        (OX_REGISTER_RE, "ox_callback_register", "lib.callback.register", "lib.callback.register"),
        (OX_AWAIT_RE, "ox_callback_call", "lib.callback.await", "lib.callback.await"),
        (OX_CALL_RE, "ox_callback_call", "lib.callback", "lib.callback"),
    ):
        for m in pat.finditer(sf.masked):
            line = sf.lines.line_at(m.start())
            value, dynamic, reason = resolve_arg_value(sf, m.end())
            name = value if value is not None else "<dynamic>"
            out.append(
                Contract(
                    id=make_id("oxcb", sf.rel, line, op, name),
                    type=ctype,
                    name=name,
                    resource=resource_name,
                    target_resource=None,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation=op,
                    confidence="EXTRACTED" if not dynamic else "INFERRED",
                    syntax=syn,
                    dynamic_name=dynamic,
                    unresolved_reason=reason,
                )
            )
    return out


def build_ox_callback_relationships(callbacks: list[Contract]) -> list[dict]:
    regs = [c for c in callbacks if c.type == "ox_callback_register"]
    calls = [c for c in callbacks if c.type == "ox_callback_call"]
    regs_by_name: dict[str, list[Contract]] = {}
    for r in regs:
        if not r.dynamic_name:
            regs_by_name.setdefault(r.name, []).append(r)

    relationships = []
    for c in calls:
        rel = {
            "id": make_id("oxrel", c.file, c.line, c.name),
            "callback": c.name,
            "caller": {"resource": c.resource, "file": c.file, "line": c.line, "operation": c.operation},
            "registrations": [],
            "status": "unresolved",
        }
        if c.dynamic_name:
            rel["status"] = "dynamic_unresolved"
            relationships.append(rel)
            continue
        candidates = regs_by_name.get(c.name, [])
        rel["registrations"] = [{"resource": r.resource, "file": r.file, "line": r.line} for r in candidates]
        if not candidates:
            rel["status"] = "missing_registration"
        elif len(candidates) == 1:
            rel["status"] = "resolved"
        else:
            rel["status"] = "resolved_multiple_registrations"
        relationships.append(rel)
    relationships.sort(key=lambda r: (r["callback"], r["status"]))
    return relationships


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

MYSQL_CALL_RE = re.compile(
    r"\bMySQL\.(query|single|scalar|insert|update|transaction)(\.await)?\s*\("
)
OXMYSQL_EXPORT_RE = re.compile(
    r"\bexports\.oxmysql:(query|insert|update|transaction)(?:Sync|Async)?\s*\("
)

SQL_COMMENT_BLOCK_RE = re.compile(r"/\*.*?\*/", re.S)
SQL_COMMENT_LINE_RE = re.compile(r"--[^\n]*")
SQL_COMMENT_HASH_RE = re.compile(r"#[^\n]*")

TABLE_PATTERNS = [
    ("select_from", re.compile(r"\bFROM\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "read"),
    ("join", re.compile(r"\bJOIN\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "read"),
    ("insert_into", re.compile(r"\bINSERT\s+(?:IGNORE\s+)?INTO\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "write"),
    ("update", re.compile(r"\bUPDATE\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "write"),
    ("delete_from", re.compile(r"\bDELETE\s+FROM\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "write"),
    ("create_table", re.compile(r"\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "schema"),
    ("alter_table", re.compile(r"\bALTER\s+TABLE\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "schema"),
    ("drop_table", re.compile(r"\bDROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "schema"),
    ("references", re.compile(r"\bREFERENCES\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "schema"),
    ("truncate_table", re.compile(r"\bTRUNCATE\s+(?:TABLE\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?", re.I), "write"),
]


def strip_sql_comments(sql: str) -> str:
    sql = SQL_COMMENT_BLOCK_RE.sub(" ", sql)
    sql = SQL_COMMENT_LINE_RE.sub(" ", sql)
    sql = SQL_COMMENT_HASH_RE.sub(" ", sql)
    return sql


def extract_tables(sql: str) -> list[tuple]:
    clean = strip_sql_comments(sql)
    found = []
    for clause, pat, category in TABLE_PATTERNS:
        for m in pat.finditer(clean):
            found.append((m.group(1), clause, category))
    return found


def scan_database_lua(sf: ScannedFile, diagnostics: dict) -> tuple[list[Contract], list[dict]]:
    ops: list[Contract] = []
    tables: list[dict] = []
    resource_name = sf.resource.name if sf.resource else None

    def handle(m: re.Match, op: str, is_await: bool, syntax: str) -> None:
        line = sf.lines.line_at(m.start())
        value, dynamic, reason = resolve_arg_value(sf, m.end())
        sql_text = value if value is not None else ""
        c = Contract(
            id=make_id("dbop", sf.rel, line, op, "await" if is_await else "call"),
            type="database_operation",
            name=op,
            resource=resource_name,
            target_resource="oxmysql",
            file=sf.rel,
            line=line,
            context=sf.context,
            operation=op,
            confidence="EXTRACTED" if not dynamic else "INFERRED",
            syntax=syntax,
            dynamic_name=dynamic,
            unresolved_reason=reason,
            extra={"await": is_await, "dynamic_sql": dynamic},
        )
        ops.append(c)
        if not dynamic and sql_text:
            for table, clause, category in extract_tables(sql_text):
                tables.append(
                    {
                        "id": make_id("dbtable", sf.rel, line, table, clause),
                        "table": table,
                        "clause": clause,
                        "category": category,
                        "operation_id": c.id,
                        "resource": resource_name,
                        "file": sf.rel,
                        "line": line,
                        "await": is_await,
                    }
                )

    for m in MYSQL_CALL_RE.finditer(sf.masked):
        handle(m, m.group(1), bool(m.group(2)), "MySQL." + m.group(1) + (".await" if m.group(2) else ""))
    for m in OXMYSQL_EXPORT_RE.finditer(sf.masked):
        handle(m, m.group(1), False, "exports.oxmysql:" + m.group(1))
    return ops, tables


def scan_sql_file(sf: ScannedFile, diagnostics: dict) -> list[dict]:
    tables = []
    for table, clause, category in extract_tables(sf.text):
        line = 1  # .sql schema files are treated as whole-file evidence; per-statement
        # line tracking is a documented Phase 1 limitation for this file type.
        tables.append(
            {
                "id": make_id("dbtable_schema", sf.rel, table, clause),
                "table": table,
                "clause": clause,
                "category": category,
                "operation_id": None,
                "resource": sf.resource.name if sf.resource else None,
                "file": sf.rel,
                "line": line,
                "await": None,
            }
        )
    return tables


# ---------------------------------------------------------------------------
# Commands and permissions
# ---------------------------------------------------------------------------

REGISTER_COMMAND_RE = re.compile(r"\bRegisterCommand\s*\(")
LIB_ADD_COMMAND_RE = re.compile(r"\blib\.addCommand\s*\(")
# No trailing '\s*' after the comma -- same reason as ASSIGN_RE above: it
# would greedily consume straight through a masked string literal.
IS_PLAYER_ACE_ALLOWED_RE = re.compile(r"\bIsPlayerAceAllowed\s*\(\s*[^,()]*,")
PERMISSION_HEURISTIC_RE = re.compile(
    r"\b([A-Za-z_][A-Za-z0-9_]*(?:Permission|HasAccess|AceAllowed)[A-Za-z0-9_]*)\s*\("
)
RESTRICTED_HINT_RE = re.compile(r",\s*(true|false)\s*\)")
PERMISSION_VALUE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.\-]{0,79}$")


def scan_commands(sf: ScannedFile, diagnostics: dict) -> tuple[list[Contract], list[Contract]]:
    commands: list[Contract] = []
    permissions: list[Contract] = []
    resource_name = sf.resource.name if sf.resource else None

    for pat, op, syn in (
        (REGISTER_COMMAND_RE, "register_command", "RegisterCommand"),
        (LIB_ADD_COMMAND_RE, "lib_add_command", "lib.addCommand"),
    ):
        for m in pat.finditer(sf.masked):
            line = sf.lines.line_at(m.start())
            value, dynamic, reason = resolve_arg_value(sf, m.end())
            name = value if value is not None else "<dynamic>"
            restricted = None
            tail = sf.masked[m.end() : m.end() + 300]
            rm = RESTRICTED_HINT_RE.search(tail)
            if rm:
                restricted = rm.group(1) == "true"
            commands.append(
                Contract(
                    id=make_id("cmd", sf.rel, line, name),
                    type="command",
                    name=name,
                    resource=resource_name,
                    target_resource=None,
                    file=sf.rel,
                    line=line,
                    context=sf.context,
                    operation=op,
                    confidence="EXTRACTED" if not dynamic else "INFERRED",
                    syntax=syn,
                    dynamic_name=dynamic,
                    unresolved_reason=reason,
                    extra={"restricted": restricted},
                )
            )

    for m in IS_PLAYER_ACE_ALLOWED_RE.finditer(sf.masked):
        line = sf.lines.line_at(m.start())
        value, dynamic, reason = resolve_arg_value(sf, m.end())
        name = value if value is not None else "<dynamic>"
        permissions.append(
            Contract(
                id=make_id("perm", sf.rel, line, name, "ace_check"),
                type="permission_check",
                name=name,
                resource=resource_name,
                target_resource=None,
                file=sf.rel,
                line=line,
                context=sf.context,
                operation="IsPlayerAceAllowed",
                confidence="EXTRACTED" if not dynamic else "INFERRED",
                syntax="IsPlayerAceAllowed(source, perm)",
                dynamic_name=dynamic,
                unresolved_reason=reason,
            )
        )

    for m in PERMISSION_HEURISTIC_RE.finditer(sf.masked):
        fn_name = m.group(1)
        line = sf.lines.line_at(m.start())
        pos = m.end()
        for _ in range(3):
            tok, status = sf.tokidx.next_literal_after(pos, max_lookahead=200)
            if status != "literal" or tok.value is None:
                break
            if PERMISSION_VALUE_RE.match(tok.value):
                permissions.append(
                    Contract(
                        id=make_id("perm", sf.rel, line, tok.value, fn_name),
                        type="permission_check",
                        name=tok.value,
                        resource=resource_name,
                        target_resource=None,
                        file=sf.rel,
                        line=line,
                        context=sf.context,
                        operation=fn_name,
                        confidence="INFERRED",
                        syntax="rank_permission_heuristic",
                        dynamic_name=False,
                    )
                )
            pos = tok.end
    return commands, permissions


ADD_ACE_RE = re.compile(r"^\s*add_ace\s+(\S+)\s+(\S+)\s+(allow|deny)\s*$", re.I)
ADD_PRINCIPAL_RE = re.compile(r"^\s*add_principal\s+(\S+)\s+(\S+)\s*$", re.I)


def scan_server_cfg_permissions(root: Path, rel_cfg: str, ignore: IgnoreMatcher, diagnostics: dict) -> list[Contract]:
    """Reads only add_ace/add_principal lines from a tracked, non-secret cfg
    file. add_principal identifier values (FiveM/license IDs) are never
    captured -- only the group they bind to -- to avoid embedding a personal
    platform identifier in a generated, potentially-shared artifact."""
    out: list[Contract] = []
    if rel_cfg in NEVER_READ_BASENAMES or ignore.is_ignored(rel_cfg):
        return out
    p = root / rel_cfg
    if not p.is_file():
        return out
    try:
        lines = p.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError as exc:
        diagnostics["errors"].append({"file": rel_cfg, "error": f"read_error: {exc.__class__.__name__}"})
        return out
    for i, line in enumerate(lines, start=1):
        m = ADD_ACE_RE.match(line)
        if m:
            principal, permission, effect = m.groups()
            out.append(
                Contract(
                    id=make_id("ace", rel_cfg, i, principal, permission, effect),
                    type="ace_permission",
                    name=permission,
                    resource=None,
                    target_resource=None,
                    file=rel_cfg,
                    line=i,
                    context="server",
                    operation=effect,
                    confidence="EXTRACTED",
                    syntax="add_ace",
                    dynamic_name=False,
                    extra={"principal": principal},
                )
            )
            continue
        m = ADD_PRINCIPAL_RE.match(line)
        if m:
            _identifier_redacted, group = m.groups()
            out.append(
                Contract(
                    id=make_id("principal", rel_cfg, i, group),
                    type="principal_binding",
                    name=group,
                    resource=None,
                    target_resource=None,
                    file=rel_cfg,
                    line=i,
                    context="server",
                    operation="add_principal",
                    confidence="EXTRACTED",
                    syntax="add_principal",
                    dynamic_name=False,
                    extra={"identifier_redacted": True},
                )
            )
    return out


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------


def git_info(root: Path, no_git: bool, verbose: bool) -> dict:
    info = {"git_available": False, "head_commit": None, "is_dirty": None, "changed_files": None}
    if no_git:
        return info
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, timeout=10
        )
        if head.returncode != 0:
            return info
        info["git_available"] = True
        info["head_commit"] = head.stdout.strip()
        status = subprocess.run(
            ["git", "status", "--porcelain=v1"], cwd=root, capture_output=True, text=True, timeout=10
        )
        info["is_dirty"] = bool(status.stdout.strip())
    except (OSError, subprocess.SubprocessError) as exc:
        if verbose:
            print(f"[cm-fivem-map] git unavailable: {exc}", file=sys.stderr)
    return info


def git_changed_files(root: Path, verbose: bool) -> Optional[list]:
    try:
        diff = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"], cwd=root, capture_output=True, text=True, timeout=10
        )
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True, timeout=10
        )
        if diff.returncode != 0:
            return None
        files = set(diff.stdout.splitlines()) | set(untracked.stdout.splitlines())
        return sorted(f.replace("\\", "/") for f in files if f)
    except (OSError, subprocess.SubprocessError) as exc:
        if verbose:
            print(f"[cm-fivem-map] git changed-files unavailable: {exc}", file=sys.stderr)
        return None


# ---------------------------------------------------------------------------
# Scan orchestration
# ---------------------------------------------------------------------------


def collect_files(root: Path, ignore: IgnoreMatcher) -> list[str]:
    files: list[str] = []
    for dirpath, dirnames, filenames in _walk(root, ignore):
        rel_dir = dirpath.relative_to(root).as_posix()
        for fn in filenames:
            rel = f"{rel_dir}/{fn}" if rel_dir else fn
            ext = Path(fn).suffix.lower()
            if ext not in SCAN_EXTS and fn not in ("fxmanifest.lua", "__resource.lua"):
                continue
            if ignore.is_ignored(rel):
                continue
            files.append(rel)
    files.sort()
    return files


def run_scan(root: Path, no_git: bool, verbose: bool, mode: str) -> dict:
    diagnostics = {"errors": [], "warnings": [], "files_scanned": 0, "files_skipped": 0}
    ignore = IgnoreMatcher(root)
    resources = discover_resources(root, ignore, verbose=verbose)
    if verbose:
        print(f"[cm-fivem-map] discovered {len(resources)} resources", file=sys.stderr)

    files = collect_files(root, ignore)

    all_events: list[Contract] = []
    all_exports: list[Contract] = []
    all_nui: list[Contract] = []
    all_ox: list[Contract] = []
    all_db_ops: list[Contract] = []
    all_db_tables: list[dict] = []
    all_commands: list[Contract] = []
    all_permissions: list[Contract] = []

    for rel in files:
        sf = load_file(root, rel, resources, diagnostics)
        if sf is None:
            diagnostics["files_skipped"] += 1
            continue
        diagnostics["files_scanned"] += 1
        if verbose:
            print(f"[cm-fivem-map] scanning {rel}", file=sys.stderr)
        ext = Path(rel).suffix.lower()
        try:
            if ext == ".lua":
                all_events.extend(scan_events(sf, diagnostics))
                all_exports.extend(scan_exports(sf, diagnostics))
                all_nui.extend(scan_nui_lua(sf, diagnostics))
                all_ox.extend(scan_ox_callbacks(sf, diagnostics))
                ops, tables = scan_database_lua(sf, diagnostics)
                all_db_ops.extend(ops)
                all_db_tables.extend(tables)
                cmds, perms = scan_commands(sf, diagnostics)
                all_commands.extend(cmds)
                all_permissions.extend(perms)
            elif ext in (".js", ".ts"):
                all_nui.extend(scan_nui_browser(sf, diagnostics))
                all_exports.extend(scan_exports(sf, diagnostics))
                all_ox.extend(scan_ox_callbacks(sf, diagnostics))
            elif ext == ".html":
                all_nui.extend(scan_nui_browser(sf, diagnostics))
            elif ext == ".sql":
                all_db_tables.extend(scan_sql_file(sf, diagnostics))
        except Exception as exc:  # pragma: no cover - defensive, keeps scan alive
            diagnostics["errors"].append({"file": rel, "error": f"extract_error: {exc.__class__.__name__}: {exc}"})

    permissions_from_cfg = scan_server_cfg_permissions(root, "server.cfg", ignore, diagnostics)
    all_permissions.extend(permissions_from_cfg)

    event_relationships = build_event_relationships(all_events)
    export_relationships = build_export_relationships(all_exports)
    nui_relationships = build_nui_relationships(all_nui)
    callback_relationships = build_ox_callback_relationships(all_ox)

    def sort_contracts(items: list[Contract]) -> list[dict]:
        return [c.to_dict() for c in sorted(items, key=lambda c: (c.file, c.line, c.type, c.name))]

    resources_out = [
        {
            "id": r.id,
            "name": r.name,
            "path": r.path,
            "owner_collection": r.owner_collection,
            "manifest_path": r.manifest_path,
            "manifest_kind": r.manifest_kind,
            "nested_manifest_candidate": r.nested_manifest_candidate,
        }
        for r in resources
    ]

    unresolved = []
    for c in all_events + all_exports + all_nui + all_ox + all_db_ops + all_commands + all_permissions:
        if c.dynamic_name or c.unresolved_reason:
            unresolved.append(
                {
                    "id": c.id,
                    "type": c.type,
                    "file": c.file,
                    "line": c.line,
                    "reason": c.unresolved_reason or "dynamic_name",
                }
            )
    unresolved.sort(key=lambda u: (u["file"], u["line"], u["type"]))

    stats = {
        "resources": len(resources),
        "events": len(all_events),
        "event_relationships": len(event_relationships),
        "exports": len(all_exports),
        "export_relationships": len(export_relationships),
        "nui_callbacks": len(all_nui),
        "nui_relationships": len(nui_relationships),
        "ox_callbacks": len(all_ox),
        "callback_relationships": len(callback_relationships),
        "database_operations": len(all_db_ops),
        "database_tables": len(all_db_tables),
        "commands": len(all_commands),
        "permissions": len(all_permissions),
        "unresolved": len(unresolved),
        "files_scanned": diagnostics["files_scanned"],
        "files_skipped": diagnostics["files_skipped"],
        "errors": len(diagnostics["errors"]),
    }

    gi = git_info(root, no_git, verbose)
    gi["mode"] = mode

    doc = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": None,  # filled in by caller
        "scanner_version": SCANNER_VERSION,
        "repository_root": ".",
        "working_tree": gi,
        "resources": resources_out,
        "events": sort_contracts(all_events),
        "event_relationships": event_relationships,
        "exports": sort_contracts(all_exports),
        "export_relationships": export_relationships,
        "nui_callbacks": sort_contracts(all_nui),
        "nui_relationships": nui_relationships,
        "ox_callbacks": sort_contracts(all_ox),
        "callback_relationships": callback_relationships,
        "database_operations": sort_contracts(all_db_ops),
        "database_tables": sorted(all_db_tables, key=lambda t: (t["file"], t["line"], t["table"])),
        "commands": sort_contracts(all_commands),
        "permissions": sort_contracts(all_permissions),
        "unresolved": unresolved,
        "diagnostics": diagnostics,
        "statistics": stats,
    }
    return doc


def filter_for_resource(doc: dict, resource_name: str) -> dict:
    """Keeps the target resource plus anything referenced by a relationship
    touching it. This is a full internal scan with a filtered *output* --
    Phase 1 does not skip file I/O for --resource (documented limitation)."""
    keep_resource_names = {resource_name}
    for rel_key in ("event_relationships",):
        for r in doc[rel_key]:
            names = set()
            if r.get("trigger"):
                names.add(r["trigger"].get("resource"))
            for h in r.get("handlers", []):
                names.add(h.get("resource"))
            if resource_name in names:
                keep_resource_names |= {n for n in names if n}
    for r in doc["export_relationships"]:
        if r["consumer"].get("resource") == resource_name or r.get("target_resource") == resource_name:
            keep_resource_names.add(r["consumer"].get("resource"))
            if r.get("target_resource"):
                keep_resource_names.add(r["target_resource"])

    def touches(item_resource, item_target=None):
        return item_resource in keep_resource_names or (item_target in keep_resource_names if item_target else False)

    out = dict(doc)
    out["resources"] = [r for r in doc["resources"] if r["name"] in keep_resource_names]
    for key in ("events", "exports", "nui_callbacks", "ox_callbacks", "database_operations", "commands", "permissions"):
        out[key] = [c for c in doc[key] if touches(c.get("resource"), c.get("target_resource"))]
    out["database_tables"] = [t for t in doc["database_tables"] if t.get("resource") in keep_resource_names]

    def rel_touches_event(r):
        names = set()
        if r.get("trigger"):
            names.add(r["trigger"].get("resource"))
        for h in r.get("handlers", []):
            names.add(h.get("resource"))
        return bool(names & keep_resource_names)

    def rel_touches_export(r):
        return r["consumer"].get("resource") in keep_resource_names or r.get("target_resource") in keep_resource_names

    def rel_touches_nui(r):
        if r.get("browser_call") and r["browser_call"].get("resource") in keep_resource_names:
            return True
        return r.get("target_resource") in keep_resource_names

    def rel_touches_ox(r):
        if r["caller"].get("resource") in keep_resource_names:
            return True
        return any(reg.get("resource") in keep_resource_names for reg in r.get("registrations", []))

    out["event_relationships"] = [r for r in doc["event_relationships"] if rel_touches_event(r)]
    out["export_relationships"] = [r for r in doc["export_relationships"] if rel_touches_export(r)]
    out["nui_relationships"] = [r for r in doc["nui_relationships"] if rel_touches_nui(r)]
    out["callback_relationships"] = [r for r in doc["callback_relationships"] if rel_touches_ox(r)]

    out["unresolved"] = [
        u for u in doc["unresolved"]
        if any(u["id"] == c.get("id") for key in
               ("events", "exports", "nui_callbacks", "ox_callbacks", "database_operations", "commands", "permissions")
               for c in out[key])
    ]

    out["statistics"] = {
        "resources": len(out["resources"]),
        "events": len(out["events"]),
        "event_relationships": len(out["event_relationships"]),
        "exports": len(out["exports"]),
        "export_relationships": len(out["export_relationships"]),
        "nui_callbacks": len(out["nui_callbacks"]),
        "nui_relationships": len(out["nui_relationships"]),
        "ox_callbacks": len(out["ox_callbacks"]),
        "callback_relationships": len(out["callback_relationships"]),
        "database_operations": len(out["database_operations"]),
        "database_tables": len(out["database_tables"]),
        "commands": len(out["commands"]),
        "permissions": len(out["permissions"]),
        "unresolved": len(out["unresolved"]),
        "files_scanned": doc["statistics"]["files_scanned"],
        "files_skipped": doc["statistics"]["files_skipped"],
        "errors": doc["statistics"]["errors"],
    }
    return out


# ---------------------------------------------------------------------------
# Summary markdown
# ---------------------------------------------------------------------------


def render_summary(doc: dict) -> str:
    s = doc["statistics"]
    lines = []
    lines.append(f"# CM FiveM Contract Scan Summary")
    lines.append("")
    lines.append(f"Generated: {doc['generated_at']} · scanner {doc['scanner_version']} · schema {doc['schema_version']}")
    lines.append(f"Mode: {doc['working_tree'].get('mode', 'full')}")
    lines.append("")
    lines.append("## Counts by contract type")
    lines.append("")
    for k in (
        "resources", "events", "exports", "nui_callbacks", "ox_callbacks",
        "database_operations", "database_tables", "commands", "permissions", "unresolved",
    ):
        lines.append(f"- {k}: {s[k]}")
    lines.append("")

    by_resource: dict[str, int] = {}
    for key in ("events", "exports", "nui_callbacks", "ox_callbacks", "database_operations", "commands", "permissions"):
        for c in doc[key]:
            r = c.get("resource")
            if r:
                by_resource[r] = by_resource.get(r, 0) + 1
    lines.append("## Counts by resource")
    lines.append("")
    for r, n in sorted(by_resource.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"- {r}: {n}")
    lines.append("")

    lines.append("## Cross-resource event relationships")
    lines.append("")
    cross_evt = [
        r for r in doc["event_relationships"]
        if r.get("trigger") and r.get("handlers")
        and any(h.get("resource") != r["trigger"].get("resource") for h in r["handlers"])
    ]
    for r in cross_evt[:50]:
        trg = r["trigger"]
        handler_resources = sorted({h.get("resource") for h in r["handlers"]})
        lines.append(f"- `{r['event']}` : {trg.get('resource')} -> {', '.join(str(x) for x in handler_resources)} ({r['status']})")
    if not cross_evt:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Cross-resource export relationships")
    lines.append("")
    cross_exp = [r for r in doc["export_relationships"] if r["consumer"].get("resource") != r.get("target_resource")]
    for r in cross_exp[:50]:
        lines.append(f"- `{r['export']}` : {r['consumer'].get('resource')} -> {r.get('target_resource')} ({r['status']})")
    if not cross_exp:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Database table ownership / consumers")
    lines.append("")
    table_resources: dict[str, set] = {}
    for t in doc["database_tables"]:
        table_resources.setdefault(t["table"], set()).add(t.get("resource") or "?")
    for table, resources in sorted(table_resources.items()):
        lines.append(f"- `{table}`: {', '.join(sorted(r for r in resources if r))}")
    if not table_resources:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Unresolved / dynamic relationships")
    lines.append("")
    lines.append(f"- total unresolved entries: {len(doc['unresolved'])}")
    reason_counts: dict[str, int] = {}
    for u in doc["unresolved"]:
        reason_counts[u["reason"]] = reason_counts.get(u["reason"], 0) + 1
    for reason, n in sorted(reason_counts.items(), key=lambda kv: -kv[1]):
        lines.append(f"  - {reason}: {n}")
    lines.append("")

    lines.append("## Missing event handlers")
    lines.append("")
    missing_evt = [r for r in doc["event_relationships"] if r["status"] == "unresolved_no_handler"]
    for r in missing_evt[:50]:
        t = r["trigger"]
        lines.append(f"- `{r['event']}` triggered at {t['file']}:{t['line']} has no matching handler")
    if not missing_evt:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Missing exports")
    lines.append("")
    missing_exp = [r for r in doc["export_relationships"] if r["status"] in ("missing_export_definition", "missing_target_resource")]
    for r in missing_exp[:50]:
        c = r["consumer"]
        lines.append(f"- `{r['export']}` used at {c['file']}:{c['line']} -> {r.get('target_resource')} ({r['status']})")
    if not missing_exp:
        lines.append("- none detected")
    lines.append("")

    lines.append("## NUI mismatches")
    lines.append("")
    nui_mismatch = [r for r in doc["nui_relationships"] if r["status"] in ("missing_lua_handler", "no_detected_browser_caller")]
    for r in nui_mismatch[:50]:
        lines.append(f"- `{r['callback']}` : {r['status']}")
    if not nui_mismatch:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Callback mismatches (ox_lib)")
    lines.append("")
    cb_mismatch = [r for r in doc["callback_relationships"] if r["status"] != "resolved"]
    for r in cb_mismatch[:50]:
        lines.append(f"- `{r['callback']}` : {r['status']}")
    if not cb_mismatch:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Potential client/server direction errors")
    lines.append("")
    dir_errors = [r for r in doc["event_relationships"] if r.get("direction_mismatch_note")]
    for r in dir_errors[:50]:
        lines.append(f"- `{r['event']}`: {r['direction_mismatch_note']}")
    if not dir_errors:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Top cross-resource dependencies")
    lines.append("")
    dep_counts: dict[tuple, int] = {}
    for r in cross_evt:
        for h in r["handlers"]:
            key = (r["trigger"].get("resource"), h.get("resource"))
            dep_counts[key] = dep_counts.get(key, 0) + 1
    for r in cross_exp:
        key = (r["consumer"].get("resource"), r.get("target_resource"))
        dep_counts[key] = dep_counts.get(key, 0) + 1
    for (a, b), n in sorted(dep_counts.items(), key=lambda kv: -kv[1])[:20]:
        lines.append(f"- {a} -> {b}: {n}")
    if not dep_counts:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Parse / read errors")
    lines.append("")
    errs = doc["diagnostics"]["errors"]
    for e in errs[:50]:
        lines.append(f"- {e['file']}: {e['error']}")
    if not errs:
        lines.append("- none")
    lines.append("")

    lines.append("## Limitations")
    lines.append("")
    lines.append("- Phase 1: `--changed` performs a full internal rescan; the changed-file list is informational only, not a true incremental update.")
    lines.append("- `--resource` performs a full internal scan and filters the output; it does not skip file I/O.")
    lines.append("- JS/TS regex-literal boundaries are not tokenized; a `/` inside a regex literal is treated as plain code (rare false-positive risk).")
    lines.append("- `.sql` schema files are attributed table-by-table without per-statement line numbers (reported as line 1).")
    lines.append("- Rank/permission-string heuristics (`*Permission*`, `*HasAccess*`, `*AceAllowed*`) are best-effort, not exhaustive.")
    lines.append("- `add_principal` identifier values (FiveM/license IDs) are intentionally never captured, only the group they bind to.")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _canonical_for_compare(doc: dict) -> dict:
    import copy

    d = copy.deepcopy(doc)
    d.pop("generated_at", None)
    if "working_tree" in d:
        d["working_tree"].pop("head_commit", None)
        d["working_tree"].pop("is_dirty", None)
    return d


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(prog="cm-fivem-map", description="Portable FiveM contract scanner")
    parser.add_argument("--root", default=".", help="repository root to scan")
    parser.add_argument("--out", default="cm-agent-out", help="output directory")
    parser.add_argument("--check", action="store_true", help="validate existing output is current without rewriting it")
    parser.add_argument("--resource", default=None, help="scan one resource plus referenced contracts")
    parser.add_argument("--changed", action="store_true", help="scan changed git files (Phase 1: full rescan, informational file list)")
    parser.add_argument("--no-git", action="store_true", help="operate without requiring git")
    parser.add_argument("--verbose", action="store_true", help="diagnostic output (no secret contents)")
    parser.add_argument("--fail-on-errors", action="store_true", help="non-zero exit for parse/read/schema failures")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    out_dir = root / args.out

    mode = "full"
    if args.resource:
        mode = f"resource:{args.resource}"
    elif args.changed:
        mode = "changed"

    doc = run_scan(root, no_git=args.no_git, verbose=args.verbose, mode=mode)

    if args.changed and not args.no_git:
        changed = git_changed_files(root, args.verbose)
        doc["working_tree"]["changed_files"] = changed
        doc["working_tree"]["changed_note"] = (
            "Phase 1: --changed performs a full rescan internally; this list is informational only."
        )
        if args.verbose and changed is not None:
            print(f"[cm-fivem-map] --changed: {len(changed)} file(s) flagged as changed (full rescan still performed)", file=sys.stderr)

    if args.resource:
        doc = filter_for_resource(doc, args.resource)

    doc["generated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    if args.check:
        contracts_path = out_dir / "fivem-contracts.json"
        if not contracts_path.exists():
            print(f"[cm-fivem-map] --check: {contracts_path} does not exist", file=sys.stderr)
            return 1
        try:
            existing = json.loads(contracts_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"[cm-fivem-map] --check: cannot read existing output: {exc}", file=sys.stderr)
            return 1
        if _canonical_for_compare(existing) == _canonical_for_compare(doc):
            print("[cm-fivem-map] --check: output is current")
            return 0
        print("[cm-fivem-map] --check: output is STALE (drift detected)", file=sys.stderr)
        old_stats = existing.get("statistics", {})
        new_stats = doc.get("statistics", {})
        for k in sorted(set(old_stats) | set(new_stats)):
            if old_stats.get(k) != new_stats.get(k):
                print(f"    {k}: {old_stats.get(k)} -> {new_stats.get(k)}", file=sys.stderr)
        return 1

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "fivem-contracts.json").write_text(
        json.dumps(doc, indent=2, ensure_ascii=False, sort_keys=False) + "\n", encoding="utf-8"
    )
    summary = render_summary(doc)
    (out_dir / "fivem-contracts-summary.md").write_text(summary, encoding="utf-8")
    metadata = {
        "schema_version": SCHEMA_VERSION,
        "scanner_version": SCANNER_VERSION,
        "generated_at": doc["generated_at"],
        "mode": mode,
        "statistics": doc["statistics"],
        "working_tree": doc["working_tree"],
    }
    (out_dir / "scan-metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(
        f"[cm-fivem-map] wrote {out_dir} "
        f"({doc['statistics']['resources']} resources, "
        f"{doc['statistics']['events']} events, "
        f"{doc['statistics']['exports']} exports, "
        f"{doc['statistics']['database_operations']} db ops, "
        f"{doc['statistics']['errors']} errors)"
    )

    if args.fail_on_errors and doc["statistics"]["errors"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
