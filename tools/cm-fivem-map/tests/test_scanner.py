"""Unit tests for cm-fivem-map's scan.py. Standard-library unittest only."""

from __future__ import annotations

import copy
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent.parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

import scan  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def read_fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


FIXTURE_RESOURCE = scan.Resource(
    id="res_fixture",
    name="fixture_res",
    path="resources/[core]/fixture_res",
    owner_collection="[core]",
    manifest_path="resources/[core]/fixture_res/fxmanifest.lua",
    manifest_kind="fxmanifest.lua",
    nested_manifest_candidate=False,
)


def make_sf(text: str, rel: str, resource=None) -> scan.ScannedFile:
    ext = Path(rel).suffix.lower()
    if ext == ".lua":
        tokens = scan.tokenize_lua(text)
    elif ext in (".js", ".ts"):
        tokens = scan.tokenize_js(text)
    elif ext == ".html":
        tokens = scan.tokenize_html(text)
    else:
        tokens = [scan.Token("code", text, 0, len(text), 1)]
    masked = scan.build_masked(text, tokens)
    sf = scan.ScannedFile(
        rel=rel,
        resource=resource,
        context=scan.infer_context(rel),
        text=text,
        tokens=tokens,
        masked=masked,
        lines=scan.LineIndex(text),
        tokidx=scan.TokenIndex(tokens),
        local_string_vars={},
    )
    if ext in (".lua", ".js", ".ts"):
        sf.local_string_vars = scan._extract_local_string_vars(sf)
    return sf


def diag() -> dict:
    return {"errors": [], "warnings": [], "files_scanned": 0, "files_skipped": 0}


CLIENT_REL = "resources/[core]/fixture_res/client.lua"
SERVER_REL = "resources/[core]/fixture_res/server.lua"
NUI_REL = "resources/[core]/fixture_res/nui.js"
MANIFEST_REL = "resources/[core]/fixture_res/fxmanifest.lua"


# ---------------------------------------------------------------------------
# Tokenizer
# ---------------------------------------------------------------------------


class TokenizerTests(unittest.TestCase):
    def test_single_and_double_quotes(self):
        text = "a = 'one' b = \"two\""
        tokens = scan.tokenize_lua(text)
        strings = [t.value for t in tokens if t.kind == "string"]
        self.assertEqual(strings, ["one", "two"])

    def test_lua_long_bracket_string(self):
        text = "local q = [[SELECT * FROM foo\nWHERE x = 1]]"
        tokens = scan.tokenize_lua(text)
        strings = [t.value for t in tokens if t.kind == "string"]
        self.assertEqual(strings, ["SELECT * FROM foo\nWHERE x = 1"])

    def test_lua_long_bracket_with_equals_level(self):
        text = "local q = [==[contains ]] inside]==]"
        tokens = scan.tokenize_lua(text)
        strings = [t.value for t in tokens if t.kind == "string"]
        self.assertEqual(strings, ["contains ]] inside"])

    def test_commented_out_call_is_masked(self):
        text = "-- RegisterNetEvent('nope')\nRegisterNetEvent('yes')"
        tokens = scan.tokenize_lua(text)
        masked = scan.build_masked(text, tokens)
        self.assertNotIn("nope", masked)
        self.assertEqual(masked.count("RegisterNetEvent"), 1)

    def test_block_comment_masked(self):
        text = "--[[ RegisterNetEvent('blocked') ]]\nRegisterNetEvent('kept')"
        tokens = scan.tokenize_lua(text)
        masked = scan.build_masked(text, tokens)
        self.assertNotIn("blocked", masked)
        self.assertIn("kept", text[text.index("RegisterNetEvent", 5) :])

    def test_js_template_literal_dynamic_flagged(self):
        text = "fetch(`https://${x}/y`)"
        tokens = scan.tokenize_js(text)
        strings = [t for t in tokens if t.kind == "string"]
        self.assertEqual(len(strings), 1)
        self.assertIsNone(strings[0].value)


# ---------------------------------------------------------------------------
# Events (registration + trigger extraction, and relationship building)
# ---------------------------------------------------------------------------


class EventExtractionTests(unittest.TestCase):
    def setUp(self):
        self.client_sf = make_sf(read_fixture("client.lua"), CLIENT_REL, FIXTURE_RESOURCE)
        self.server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        self.client_events = scan.scan_events(self.client_sf, diag())
        self.server_events = scan.scan_events(self.server_sf, diag())

    def test_double_and_single_quote_registration_captured(self):
        names = {c.name for c in self.client_events if c.type == "event_registration"}
        self.assertIn("fixture:clientReady", names)
        self.assertIn("fixture:multilineEvent", names)

    def test_commented_out_event_not_extracted(self):
        names = {c.name for c in self.client_events}
        self.assertNotIn("fixture:commentedOut", names)

    def test_dynamic_computed_event_name_unresolved(self):
        dynamic = [
            c for c in self.client_events
            if c.type == "event_registration" and c.operation == "register_net_event" and c.dynamic_name
        ]
        self.assertTrue(any(c.unresolved_reason == "non_literal_argument" for c in dynamic))

    def test_multiline_call_line_number_is_declaration_line(self):
        multi = next(c for c in self.client_events if c.name == "fixture:multilineEvent")
        # RegisterNetEvent( opens a couple lines above the fixture's opening comment block;
        # we only assert it lands on the "RegisterNetEvent(" line, not the string's own line.
        decl_line = read_fixture("client.lua").splitlines().index("RegisterNetEvent(") + 1
        self.assertEqual(multi.line, decl_line)

    def test_server_has_two_handlers_for_do_thing(self):
        handlers = [
            c for c in self.server_events
            if c.type == "event_registration" and c.operation == "add_event_handler" and c.name == "fixture:doThing"
        ]
        self.assertEqual(len(handlers), 2)

    def test_trigger_extracted(self):
        triggers = [c for c in self.client_events if c.type == "event_trigger"]
        self.assertTrue(any(c.name == "fixture:doThing" and c.operation == "trigger_server_event" for c in triggers))


class EventRelationshipTests(unittest.TestCase):
    def setUp(self):
        client_sf = make_sf(read_fixture("client.lua"), CLIENT_REL, FIXTURE_RESOURCE)
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        self.events = scan.scan_events(client_sf, diag()) + scan.scan_events(server_sf, diag())
        self.rels = scan.build_event_relationships(self.events)

    def test_client_to_server_resolves_two_handlers(self):
        rel = next(r for r in self.rels if r["event"] == "fixture:doThing" and r["trigger"])
        self.assertEqual(rel["direction"], "client_to_server")
        self.assertEqual(rel["handler_count"], 2)
        self.assertEqual(rel["status"], "resolved_multiple")

    def test_server_to_client_resolves_one_handler(self):
        rel = next(r for r in self.rels if r["event"] == "fixture:clientReady" and r["trigger"])
        self.assertEqual(rel["direction"], "server_to_client")
        self.assertEqual(rel["handler_count"], 1)
        self.assertEqual(rel["status"], "resolved")

    def test_relationships_are_sorted_deterministically(self):
        rels2 = scan.build_event_relationships(list(self.events))
        self.assertEqual(self.rels, rels2)


# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------


class ExportTests(unittest.TestCase):
    def test_dot_and_bracket_consumer_syntax(self):
        text = (
            "exports.other_res:DoThing(1)\n"
            "exports['other_res']:DoOther(2)\n"
            "exports[\"other_res\"]:DoThird(3)\n"
            "local rv = getResName()\n"
            "exports[rv]:Dynamic(4)\n"
        )
        sf = make_sf(text, SERVER_REL, FIXTURE_RESOURCE)
        contracts = scan.scan_exports(sf, diag())
        consumers = [c for c in contracts if c.type == "export_consumer"]
        self.assertEqual(len(consumers), 4)
        by_op = {c.operation for c in consumers}
        self.assertIn("exports_dot", by_op)
        self.assertIn("exports_bracket_string", by_op)
        self.assertIn("exports_bracket_dynamic", by_op)
        dynamic = [c for c in consumers if c.operation == "exports_bracket_dynamic"]
        self.assertEqual(len(dynamic), 1)
        self.assertTrue(dynamic[0].dynamic_name)

    def test_bracket_dot_property_call_form_resolved(self):
        # Real-world FiveM code also calls a bracket-form export via a dot
        # (property access), not only the colon form -- e.g.
        # exports['cm-core'].GetPlayer(src), observed in this repository.
        text = "exports['cm-core'].GetPlayer(src)\n"
        sf = make_sf(text, SERVER_REL, FIXTURE_RESOURCE)
        contracts = scan.scan_exports(sf, diag())
        consumer = next(c for c in contracts if c.type == "export_consumer")
        self.assertEqual(consumer.name, "GetPlayer")
        self.assertEqual(consumer.target_resource, "cm-core")

    def test_export_definition_and_relationship_resolved(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        defs = scan.scan_exports(server_sf, diag())
        consumer_text = "exports.fixture_res:GetFixtureValue()\n"
        other_resource = scan.Resource(
            id="res_other", name="other_res", path="resources/[core]/other_res",
            owner_collection="[core]", manifest_path="x", manifest_kind="fxmanifest.lua",
            nested_manifest_candidate=False,
        )
        # server.lua's export is server-context; consume from a server-context
        # file too so this exercises plain resolution, not the realm-mismatch
        # detection (exports do not cross the client/server boundary in
        # FiveM, so a server export consumed by client code is a genuine
        # mismatch -- covered separately below).
        consumer_sf = make_sf(consumer_text, "resources/[core]/other_res/server.lua", other_resource)
        uses = scan.scan_exports(consumer_sf, diag())
        rels = scan.build_export_relationships(defs + uses)
        rel = next(r for r in rels if r["export"] == "GetFixtureValue")
        self.assertEqual(rel["status"], "resolved")
        self.assertEqual(rel["target_resource"], "fixture_res")

    def test_export_realm_mismatch_detected(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        defs = scan.scan_exports(server_sf, diag())
        consumer_text = "exports.fixture_res:GetFixtureValue()\n"
        consumer_sf = make_sf(consumer_text, "resources/[core]/other_res/client.lua", None)
        uses = scan.scan_exports(consumer_sf, diag())
        rels = scan.build_export_relationships(defs + uses)
        rel = next(r for r in rels if r["export"] == "GetFixtureValue")
        self.assertEqual(rel["status"], "resolved_context_mismatch")

    def test_missing_export_definition_reported(self):
        consumer_text = "exports.fixture_res:DoesNotExist()\n"
        consumer_sf = make_sf(consumer_text, "resources/[core]/other_res/client.lua", None)
        uses = scan.scan_exports(consumer_sf, diag())
        rels = scan.build_export_relationships(uses)
        rel = rels[0]
        self.assertIn(rel["status"], ("missing_export_definition", "missing_target_resource"))


# ---------------------------------------------------------------------------
# NUI
# ---------------------------------------------------------------------------


class NuiTests(unittest.TestCase):
    def test_fetch_resolves_to_registernuicallback(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        nui_sf = make_sf(read_fixture("nui.js"), NUI_REL, FIXTURE_RESOURCE)
        registrations = scan.scan_nui_lua(server_sf, diag())
        calls = scan.scan_nui_browser(nui_sf, diag())
        rels = scan.build_nui_relationships(registrations + calls)
        resolved = next(r for r in rels if r["callback"] == "fixtureNuiAction")
        self.assertEqual(resolved["status"], "resolved")
        orphan_call = next(r for r in rels if r["callback"] == "fixtureOrphanRequest")
        self.assertEqual(orphan_call["status"], "missing_lua_handler")
        unused_handler = next(r for r in rels if r["callback"] == "fixtureUnusedCallback")
        self.assertEqual(unused_handler["status"], "no_detected_browser_caller")


# ---------------------------------------------------------------------------
# ox_lib callbacks
# ---------------------------------------------------------------------------


class OxCallbackTests(unittest.TestCase):
    def test_register_and_await_resolve(self):
        client_sf = make_sf(read_fixture("client.lua"), CLIENT_REL, FIXTURE_RESOURCE)
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        cbs = scan.scan_ox_callbacks(server_sf, diag()) + scan.scan_ox_callbacks(client_sf, diag())
        regs = [c for c in cbs if c.type == "ox_callback_register"]
        calls = [c for c in cbs if c.type == "ox_callback_call"]
        self.assertTrue(any(c.name == "fixture:askServer" for c in regs))
        self.assertTrue(any(c.name == "fixture:askServer" and c.operation == "lib.callback.await" for c in calls))
        rels = scan.build_ox_callback_relationships(cbs)
        rel = next(r for r in rels if r["callback"] == "fixture:askServer")
        self.assertEqual(rel["status"], "resolved")

    def test_missing_registration_reported(self):
        text = "lib.callback.await('nowhere:defined', false)\n"
        sf = make_sf(text, CLIENT_REL, FIXTURE_RESOURCE)
        cbs = scan.scan_ox_callbacks(sf, diag())
        rels = scan.build_ox_callback_relationships(cbs)
        self.assertEqual(rels[0]["status"], "missing_registration")


# ---------------------------------------------------------------------------
# Database / SQL
# ---------------------------------------------------------------------------


class DatabaseTests(unittest.TestCase):
    def test_static_and_local_var_sql_resolved(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        ops, tables = scan.scan_database_lua(server_sf, diag())
        static_op = next(o for o in ops if o.operation == "query")
        self.assertFalse(static_op.dynamic_name)
        local_var_op = next(o for o in ops if o.operation == "insert")
        self.assertFalse(local_var_op.dynamic_name)
        table_names = {t["table"] for t in tables}
        self.assertIn("fixture_items", table_names)
        self.assertIn("fixture_events", table_names)

    def test_fully_dynamic_sql_marked_dynamic(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        ops, _ = scan.scan_database_lua(server_sf, diag())
        dyn_op = next(o for o in ops if o.operation == "update")
        self.assertTrue(dyn_op.dynamic_name)

    def test_await_flag_captured(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        ops, _ = scan.scan_database_lua(server_sf, diag())
        query_op = next(o for o in ops if o.operation == "query")
        self.assertTrue(query_op.extra["await"])
        insert_op = next(o for o in ops if o.operation == "insert")
        self.assertFalse(insert_op.extra["await"])

    def test_sql_table_extraction_from_schema_file(self):
        sql = read_fixture("schema.sql")
        found = scan.extract_tables(sql)
        clauses = {(table, clause) for table, clause, _cat in found}
        self.assertIn(("fixture_items", "create_table"), clauses)
        self.assertIn(("fixture_events", "create_table"), clauses)
        self.assertIn(("fixture_items", "references"), clauses)
        self.assertIn(("fixture_events", "alter_table"), clauses)
        # the commented-out DROP TABLE must never be extracted
        self.assertNotIn(("fixture_items", "drop_table"), clauses)

    def test_oxmysql_export_style_detected(self):
        text = "exports.oxmysql:query('SELECT * FROM oxm_table', {})\n"
        sf = make_sf(text, SERVER_REL, FIXTURE_RESOURCE)
        ops, tables = scan.scan_database_lua(sf, diag())
        self.assertEqual(len(ops), 1)
        self.assertEqual(ops[0].syntax, "exports.oxmysql:query")
        self.assertTrue(any(t["table"] == "oxm_table" for t in tables))


# ---------------------------------------------------------------------------
# Commands and permissions
# ---------------------------------------------------------------------------


class CommandPermissionTests(unittest.TestCase):
    def test_command_and_ace_check_extracted(self):
        server_sf = make_sf(read_fixture("server.lua"), SERVER_REL, FIXTURE_RESOURCE)
        commands, permissions = scan.scan_commands(server_sf, diag())
        self.assertTrue(any(c.name == "fixturecmd" and c.operation == "register_command" for c in commands))
        self.assertTrue(any(p.name == "fixture.admin" and p.operation == "IsPlayerAceAllowed" for p in permissions))

    def test_dot_alone_is_not_treated_as_permission(self):
        text = "print('just.a.dotted.string, not a permission check')\n"
        sf = make_sf(text, SERVER_REL, FIXTURE_RESOURCE)
        _commands, permissions = scan.scan_commands(sf, diag())
        self.assertEqual(permissions, [])


# ---------------------------------------------------------------------------
# Ignore engine / resource discovery (integration, uses a temp tree)
# ---------------------------------------------------------------------------


class TempRepoMixin:
    def build_temp_repo(self) -> Path:
        root = Path(tempfile.mkdtemp(prefix="cmfivemmap_"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)

        def write(rel: str, content: str) -> None:
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")

        # the real fixture resource, so relationships/tables show up end to end
        for name in ("client.lua", "server.lua", "fxmanifest.lua", "nui.js", "schema.sql"):
            write(f"resources/[core]/fixture_res/{name}", read_fixture(name))

        # nested manifest candidate
        write(
            "resources/[core]/fixture_res/vendor/fxmanifest.lua",
            "fx_version 'cerulean'\ngame 'gta5'\nname 'vendor_nested'\n",
        )

        # bracket collection folders that must never become resources
        write("resources/[mlo]/some_mlo/fxmanifest.lua", "fx_version 'cerulean'\nname 'some_mlo'\n")
        write("resources/[core]/bcrypt/dist/fxmanifest.lua", "fx_version 'cerulean'\nname 'bcrypt_dist'\n")

        # ignored/secret/runtime paths that must never be ingested
        write("server.local.cfg", "set mysql_connection_string \"mysql://secret\"\n")
        write("cache/leftover.lua", "RegisterNetEvent('should:not:appear')\n")
        write(
            "resources/[core]/fixture_res/stream/leftover.lua",
            "RegisterNetEvent('stream:should:not:appear')\n",
        )
        write("local-security-backup/dump.cfg", "add_ace group.admin secret.thing allow\n")

        (root / ".gitignore").write_text("cm-agent-out/\n", encoding="utf-8")
        return root


class IgnoreAndDiscoveryTests(TempRepoMixin, unittest.TestCase):
    def test_bracket_collection_paths_matched_literally(self):
        root = self.build_temp_repo()
        ignore = scan.IgnoreMatcher(root)
        resources = scan.discover_resources(root, ignore)
        names = {r.name for r in resources}
        self.assertIn("fixture_res", names)
        self.assertNotIn("[core]", names)
        self.assertNotIn("[mlo]", names)
        # [mlo]/ is always-excluded -> its manifest is never even discovered
        self.assertNotIn("some_mlo", names)
        self.assertNotIn("bcrypt_dist", names)
        fixture = next(r for r in resources if r.name == "fixture_res")
        self.assertEqual(fixture.owner_collection, "[core]")

    def test_nested_manifest_candidate_flagged(self):
        root = self.build_temp_repo()
        ignore = scan.IgnoreMatcher(root)
        resources = scan.discover_resources(root, ignore)
        nested = next(r for r in resources if r.name == "vendor")
        self.assertTrue(nested.nested_manifest_candidate)
        outer = next(r for r in resources if r.name == "fixture_res")
        self.assertFalse(outer.nested_manifest_candidate)

    def test_ignored_secret_and_runtime_paths_excluded_from_scan(self):
        root = self.build_temp_repo()
        ignore = scan.IgnoreMatcher(root)
        files = scan.collect_files(root, ignore)
        self.assertNotIn("server.local.cfg", files)
        self.assertFalse(any("cache/leftover.lua" in f for f in files))
        self.assertFalse(any("/stream/" in f for f in files))
        self.assertFalse(any("bcrypt/dist" in f for f in files))
        self.assertFalse(any("[mlo]" in f for f in files))

    def test_never_read_basename_refuses_even_direct_call(self):
        root = self.build_temp_repo()
        result = scan.load_file(root, "server.local.cfg", [], diag())
        self.assertIsNone(result)

    def test_deterministic_output_across_runs(self):
        root = self.build_temp_repo()
        doc1 = scan.run_scan(root, no_git=True, verbose=False, mode="full")
        doc2 = scan.run_scan(root, no_git=True, verbose=False, mode="full")
        doc1.pop("generated_at", None)
        doc2.pop("generated_at", None)
        self.assertEqual(doc1, doc2)

    def test_full_scan_never_ingests_secret_or_excluded_content(self):
        root = self.build_temp_repo()
        doc = scan.run_scan(root, no_git=True, verbose=False, mode="full")
        dumped = json.dumps(doc)
        self.assertNotIn("mysql://secret", dumped)
        self.assertNotIn("should:not:appear", dumped)
        self.assertNotIn("stream:should:not:appear", dumped)
        self.assertNotIn("secret.thing", dumped)


if __name__ == "__main__":
    unittest.main()
