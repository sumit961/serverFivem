#!/usr/bin/env python3
"""Read-only regression/contract checks for the cm-house / cm-family hardening
and cleanup-ownership passes.

This is a static source scanner, not a runtime test: it protects against a
future refactor silently reintroducing one of the specific defects already
found and fixed (an auth check moved after a side effect, a privacy leak
re-added to a replicated table, the old direct cross-resource DELETE pattern
coming back, a stale doc claim, etc). It does not require a running FXServer,
a database, or a mocking framework, and it changes nothing.

Exit code: 0 if no errors (warnings are non-fatal, matching tools/cm-validate).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

TOKEN = re.compile(r"\b(function|if|for|while|end)\b")


def mask_non_code(text: str) -> str:
    """Return `text` with comments, quoted strings, and long-bracket strings
    replaced by spaces (newlines preserved), keeping every other character's
    offset identical to the original.

    Needed because English error-message strings in this codebase routinely
    contain bare words like "for" ("Wait for the transfer") or "end"
    ("append") -- a keyword counter that does not mask string content will
    treat those as real Lua keywords and never re-balance. The event/export
    name strings we search FOR (e.g. 'cm-house:server:buyHouse') live inside
    quotes too, so callers search the ORIGINAL text for a start position and
    only use this masked text to count keywords from that same offset.
    """
    out = list(text)
    i, n = 0, len(text)

    def mask_range(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        ch = text[i]
        if ch == "-" and text[i:i + 2] == "--":
            if text[i:i + 4] == "--[[":
                end = text.find("]]", i + 4)
                end = n if end == -1 else end + 2
            else:
                end = text.find("\n", i)
                end = n if end == -1 else end
            mask_range(i, end)
            i = end
            continue
        if ch in ("'", '"'):
            quote = ch
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == quote:
                    j += 1
                    break
                j += 1
            mask_range(i, j)
            i = j
            continue
        if ch == "[" and i + 1 < n and text[i + 1] in ("[", "="):
            j = i + 1
            eqs = 0
            while j < n and text[j] == "=":
                eqs += 1
                j += 1
            if j < n and text[j] == "[":
                close = "]" + ("=" * eqs) + "]"
                end = text.find(close, j + 1)
                end = n if end == -1 else end + len(close)
                mask_range(i, end)
                i = end
                continue
        i += 1
    return "".join(out)


class LuaFile:
    """A source file plus its comment/string-masked twin. Both have identical
    length, so an offset found in one is valid in the other."""

    def __init__(self, path: Path):
        self.path = path
        self.original = path.read_text(encoding="utf-8-sig", errors="replace")
        self.masked = mask_non_code(self.original)

    def find_block(self, start_pattern: str) -> tuple[int, int] | None:
        """Locate start_pattern in the ORIGINAL text (so it can match a
        quoted event/export name), then use the MASKED text from that same
        offset to find the balancing `end` via a function/if/for/while depth
        counter. Returns (start, end) offsets valid in either text."""
        match = re.search(start_pattern, self.original)
        if not match:
            return None
        start = match.start()
        depth = 0
        for tok in TOKEN.finditer(self.masked, start):
            if tok.group(1) == "end":
                depth -= 1
                if depth == 0:
                    return start, tok.end()
            else:
                depth += 1
        return None

    def slice(self, block: tuple[int, int]) -> str:
        return self.original[block[0]:block[1]]


def check_weapon_recovery_auth(house_server: Path, errors: list[str]) -> None:
    lf = LuaFile(house_server / "sv_weapon_storage.lua")
    for export_name in ("ListWeaponStorageRecovery", "RestoreWeaponStorageRecovery"):
        block = lf.find_block(rf"exports\('{export_name}',\s*function")
        if not block:
            errors.append(f"sv_weapon_storage.lua: could not locate export {export_name} to check auth ordering")
            continue
        body = lf.slice(block)
        auth_pos = body.find("requireRecoveryIntegration()")
        first_db_pos = body.find("MySQL.")
        if auth_pos == -1:
            errors.append(f"sv_weapon_storage.lua: {export_name} no longer calls requireRecoveryIntegration() -- authorization gate missing")
        elif first_db_pos != -1 and auth_pos > first_db_pos:
            errors.append(f"sv_weapon_storage.lua: {export_name} performs a DB call before requireRecoveryIntegration() -- auth gate moved after a side effect")


def check_durability_preserved(house_server: Path, errors: list[str]) -> None:
    lf = LuaFile(house_server / "sv_weapon_storage.lua")
    block = lf.find_block(r"lib\.callback\.register\('cm-house:server:weaponStorageTransfer',\s*function")
    if not block:
        errors.append("sv_weapon_storage.lua: could not locate weaponStorageTransfer callback to check durability handling")
        return
    body = lf.slice(block)
    guarded = re.search(
        r"if\s+def\.itemType\s*==\s*'weapon'\s*then\s*.*?if\s+REQUIRE_FULL_DURABILITY\s+then\s*.*?lockerMeta\.durability\s*=\s*REQUIRED_DURABILITY\s*.*?else\s*.*?weaponDurability\(meta,\s*row\)",
        body, re.S,
    )
    if not guarded:
        errors.append(
            "sv_weapon_storage.lua: weaponStorageTransfer no longer guards "
            "'lockerMeta.durability = REQUIRED_DURABILITY' behind "
            "REQUIRE_FULL_DURABILITY with a real-value else branch -- this is "
            "the exact shape of the silent-100%-repair bug that was fixed"
        )


def check_cooldown_key(house_server: Path, errors: list[str]) -> None:
    text = (house_server / "sv_weapon_storage.lua").read_text(encoding="utf-8-sig", errors="replace")
    if "('%s:%s:%s'):format(tostring(ctx.cid), tostring(houseId), tostring(index))" in text:
        errors.append("sv_weapon_storage.lua: withdrawal cooldown key regressed to the per-storage-point (cid:houseId:index) format")
    if "('%s:%s'):format(tostring(ctx.cid), tostring(houseId))" not in text:
        errors.append("sv_weapon_storage.lua: expected per-house (cid:houseId) withdrawal cooldown key not found")


def check_stash_proximity(house_server: Path, errors: list[str]) -> None:
    lf = LuaFile(house_server / "sv_interior.lua")
    block = lf.find_block(r"RegisterNetEvent\('cm-house:server:openStash',\s*function")
    if not block:
        errors.append("sv_interior.lua: could not locate openStash handler to check proximity validation")
        return
    if "playerNear(" not in lf.slice(block):
        errors.append("sv_interior.lua: openStash no longer validates physical proximity to the stash")


def check_buy_sell_proximity(house_server: Path, errors: list[str]) -> None:
    lf = LuaFile(house_server / "sv_door.lua")
    for cb_name in ("buyHouse", "sellHouse"):
        block = lf.find_block(rf"lib\.callback\.register\('cm-house:server:{cb_name}',\s*function")
        if not block:
            errors.append(f"sv_door.lua: could not locate {cb_name} callback to check proximity ordering")
            continue
        body = lf.slice(block)
        prox_pos = body.find("playerNearHouseDoor(")
        if prox_pos == -1:
            errors.append(f"sv_door.lua: {cb_name} no longer calls playerNearHouseDoor -- proximity check removed")
            continue
        for mutation in ("MySQL.transaction.await", "TakeMoney(", "MySQL.update.await"):
            pos = body.find(mutation)
            if pos != -1 and pos < prox_pos:
                errors.append(f"sv_door.lua: {cb_name} reaches '{mutation}' before the playerNearHouseDoor proximity check")
                break


def check_owner_houses_ordering(house_server: Path, errors: list[str]) -> None:
    lf = LuaFile(house_server / "sv_family_lifecycle.lua")
    block = lf.find_block(r"function FL\.TransferFamilyHouseOwnership")
    if not block:
        errors.append("sv_family_lifecycle.lua: could not locate FL.TransferFamilyHouseOwnership to check OwnerHouses ordering")
        return
    body = lf.slice(block)
    fail_pos = body.find("return false, 'house_ownership_update_failed'")
    cache_pos = body.find("OwnerHouses[")
    if fail_pos == -1:
        errors.append("sv_family_lifecycle.lua: TransferFamilyHouseOwnership no longer guards on the DB update result")
    if cache_pos == -1:
        errors.append("sv_family_lifecycle.lua: TransferFamilyHouseOwnership no longer updates the OwnerHouses reverse index")
    elif fail_pos != -1 and cache_pos < fail_pos:
        errors.append("sv_family_lifecycle.lua: OwnerHouses cache is touched before the DB-update failure check -- could mutate cache on a failed transfer")


def check_cm_house_never_deletes_family_tables(house_root: Path, errors: list[str]) -> None:
    for lua_file in house_root.rglob("*.lua"):
        if "cache" in lua_file.parts:
            continue
        text = lua_file.read_text(encoding="utf-8-sig", errors="replace")
        if re.search(r"DELETE\s+FROM\s+cm_family_", text, re.I):
            errors.append(f"{lua_file.relative_to(house_root)}: cm-house directly deletes a cm_family_* table again -- this is the exact ownership-boundary regression that was fixed")


def check_family_state_allowlist(family_server: Path, errors: list[str]) -> None:
    lf = LuaFile(family_server / "sv_core.lua")
    if "local publicState = {" not in lf.masked:
        errors.append("sv_core.lua: could not locate BuildFamilyMemberState's publicState table to check the replication allowlist")
        return
    # A plain table literal has no function/if/for/while keywords, so match
    # braces directly here (on the masked text, so a value string like
    # 'weapon_storage.access' can't itself contain a stray '{' or '}').
    start = lf.masked.index("local publicState = {")
    depth = 0
    end = None
    for i, ch in enumerate(lf.masked[start:], start):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        errors.append("sv_core.lua: could not find the closing brace of BuildFamilyMemberState's publicState table")
        return
    body = lf.slice((start, end))
    forbidden = ("permission", "permissionmap", "perms")
    lowered = body.lower()
    for word in forbidden:
        if word in lowered:
            errors.append(f"sv_core.lua: BuildFamilyMemberState's replicated publicState table contains '{word}' -- the permission-map privacy fix may have regressed")

    export_block = lf.find_block(r"exports\('GetMemberIdentity',\s*function")
    if export_block:
        export_body = lf.slice(export_block)
        if re.search(r"return\s+BuildFamilyMemberState\(", export_body):
            errors.append("sv_core.lua: GetMemberIdentity does 'return BuildFamilyMemberState(...)' -- a Lua tail call that would forward the private permissions return value to any caller")


def check_finalize_family_deletion_ordering(family_server: Path, errors: list[str]) -> None:
    lf = LuaFile(family_server / "sv_core.lua")
    block = lf.find_block(r"exports\('FinalizeHouseFamilyDeletion',\s*function")
    if not block:
        errors.append("sv_core.lua: could not locate FinalizeHouseFamilyDeletion export to check auth/ordering")
        return
    body = lf.slice(block)
    auth_pos = body.find("houseLifecycleInvokerAllowed()")
    delete_pos = body.find("CMFamilyDeleteFamilyRows(familyId)")
    cache_pos = body.find("MemberByCid[cid] = nil")
    if auth_pos == -1:
        errors.append("sv_core.lua: FinalizeHouseFamilyDeletion no longer checks houseLifecycleInvokerAllowed()")
    if delete_pos == -1:
        errors.append("sv_core.lua: FinalizeHouseFamilyDeletion no longer calls the authoritative CMFamilyDeleteFamilyRows")
    if cache_pos == -1:
        errors.append("sv_core.lua: FinalizeHouseFamilyDeletion no longer clears MemberByCid")
    if -1 not in (auth_pos, delete_pos) and auth_pos > delete_pos:
        errors.append("sv_core.lua: FinalizeHouseFamilyDeletion deletes family rows before checking authorization")
    if -1 not in (delete_pos, cache_pos) and delete_pos > cache_pos:
        errors.append("sv_core.lua: FinalizeHouseFamilyDeletion clears runtime caches before the authoritative DB delete -- a failed delete would still wipe live state")


def check_dead_meeting_files(family_root: Path, errors: list[str]) -> None:
    for stale in ("server/sv_meeting.lua", "client/cl_meeting.lua"):
        if (family_root / stale).exists():
            errors.append(f"cm-family/{stale}: removed dead file has reappeared")
    manifest = (family_root / "fxmanifest.lua").read_text(encoding="utf-8-sig", errors="replace")
    if "sv_meeting" in manifest or "cl_meeting" in manifest:
        errors.append("cm-family/fxmanifest.lua: references a removed meeting file")


def check_audit_pending_git_state(repo_root: Path, warnings: list[str], errors: list[str]) -> None:
    rel = "resources/[core]/cm-family/audit_pending.json"
    try:
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", rel],
            cwd=repo_root, capture_output=True, text=True,
        )
    except FileNotFoundError:
        warnings.append("git not available on PATH -- skipped audit_pending.json tracked-state check")
        return
    if tracked.returncode == 0:
        errors.append("audit_pending.json is tracked by git again (only reporting tracked/untracked status, not contents)")
    gitignore = (repo_root / ".gitignore").read_text(encoding="utf-8-sig", errors="replace")
    if rel not in gitignore.replace("\\[", "[").replace("\\]", "]"):
        errors.append(".gitignore no longer contains an exact-path ignore rule for cm-family/audit_pending.json")


def check_admin_integration_contract(house_root: Path, admin_root: Path, errors: list[str]) -> None:
    admin_lua = (house_root / "server" / "sv_admin.lua").read_text(encoding="utf-8-sig", errors="replace")
    for symbol in ("RegisterDevTool", "OpenAdminPanel", "OpenHouseCreator", "cm-house:dev:openAdmin"):
        if symbol not in admin_lua:
            errors.append(f"sv_admin.lua: documented symbol '{symbol}' no longer exists in source")
    if admin_root.exists():
        for lua_file in admin_root.rglob("*.lua"):
            text = lua_file.read_text(encoding="utf-8-sig", errors="replace")
            for stale in ("openHousePanel", "startHouseCreator"):
                if stale in text:
                    errors.append(f"{lua_file.relative_to(admin_root)}: cm-admin now implements '{stale}' -- update docs/ADMIN_INTEGRATION_v1.7.0.md, it currently documents this as never implemented")


def check_version_changelog_consistency(resource_root: Path, name: str, errors: list[str]) -> str | None:
    manifest = (resource_root / "fxmanifest.lua").read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r"version\s+'([\d.]+)'", manifest)
    if not match:
        errors.append(f"{name}/fxmanifest.lua: could not find a version string")
        return None
    version = match.group(1)
    if not (resource_root / f"CHANGELOG_v{version}.md").exists():
        errors.append(f"{name}: fxmanifest version {version} has no matching CHANGELOG_v{version}.md")
    return version


def check_readme_version(family_root: Path, fx_version: str | None, errors: list[str]) -> None:
    if not fx_version:
        return
    readme = (family_root / "README.md").read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r"^#\s*cm-family\s+v([\d.]+)", readme, re.M)
    if match and match.group(1) != fx_version:
        errors.append(f"cm-family/README.md: title says v{match.group(1)} but fxmanifest.lua says v{fx_version}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root")
    args = parser.parse_args()
    root = Path(args.root).resolve()

    house_root = root / "resources" / "[core]" / "cm-house"
    family_root = root / "resources" / "[core]" / "cm-family"
    admin_root = root / "resources" / "[core]" / "cm-admin"

    errors: list[str] = []
    warnings: list[str] = []

    check_weapon_recovery_auth(house_root / "server", errors)
    check_durability_preserved(house_root / "server", errors)
    check_cooldown_key(house_root / "server", errors)
    check_stash_proximity(house_root / "server", errors)
    check_buy_sell_proximity(house_root / "server", errors)
    check_owner_houses_ordering(house_root / "server", errors)
    check_cm_house_never_deletes_family_tables(house_root, errors)
    check_family_state_allowlist(family_root / "server", errors)
    check_finalize_family_deletion_ordering(family_root / "server", errors)
    check_dead_meeting_files(family_root, errors)
    check_audit_pending_git_state(root, warnings, errors)
    check_admin_integration_contract(house_root, admin_root, errors)

    house_version = check_version_changelog_consistency(house_root, "cm-house", errors)
    family_version = check_version_changelog_consistency(family_root, "cm-family", errors)
    check_readme_version(family_root, family_version, errors)

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    print(f"cm-house/cm-family contract check complete: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
