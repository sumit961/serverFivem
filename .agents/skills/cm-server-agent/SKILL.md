---
name: cm-server-agent
description: Use for diagnosing, reviewing, planning, changing, securing, or testing any resource in this CM FiveM server repository. Maps affected resources and contracts using AGENTS.md, agent-docs, the CM FiveM contract scanner, and Graphify before code changes; preserves unrelated work and requires proportionate validation and manual FiveM runtime tests.
---

# CM Server Agent

## When to use

Trigger for:

- any `cm-*` resource work
- FiveM bugs
- feature implementation
- architecture review
- security review
- database/schema changes
- NUI changes
- event/export/callback work
- cross-resource integration
- performance investigation
- release preparation

Do not trigger merely for generic questions unrelated to this repository.

## Sources of truth

Precedence, highest first:

1. The user's current explicit request
2. Applicable `AGENTS.md`
3. Actual source code and database migrations
4. `cm-agent-out/fivem-contracts.json`
5. `agent-docs/resource-registry.yaml`
6. `graphify-out/graph.json` and scoped Graphify queries
7. Historical summaries or inferred relationships

Source code wins over stale generated maps. The CM scanner's relationships
are authoritative only for the syntax families it extracts (see
`references/intelligence-workflow.md`) — it is silent on everything else,
not wrong about it. Graphify is supplemental for generic call graphs only.
Any inferred (not directly read) relationship must be labelled as such when
reported. **Never treat Graphify as authoritative for FiveM events, exports,
NUI, or MySQL/oxmysql usage** — it has no model of FiveM's runtime; the CM
scanner exists specifically because Graphify cannot see these.

## Initial workflow

For every non-trivial repository task:

1. Read root `AGENTS.md`.
2. Check Git status and identify unrelated working-tree changes to preserve.
3. Classify the request: diagnose / review / plan / change / release.
4. Identify named resources and their likely consumers.
5. Check whether generated intelligence exists and is current (`--check`).
6. Query the CM contract map for events, exports, callbacks, database
   tables, and permissions relevant to the request.
7. Use scoped Graphify queries for generic functions/call paths.
8. Inspect the actual source files before reaching conclusions — generated
   maps summarize evidence, they do not replace reading the code.
9. Present a concise affected-resource/contract plan before broad changes.
10. Implement only when authorised (see the diagnosis/review/change
    boundary below).

## Map freshness

**CM contract map** (see `references/intelligence-workflow.md` for full
usage):

```bash
# check if current, without rewriting
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out --check

# full refresh
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out

# one resource plus what references it
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out --resource cm-house

# changed-files mode
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out --changed
```

State honestly that Phase 1 `--resource` and `--changed` may perform a full
internal rescan while only filtering the *output* — this is documented
scanner behavior, not an incremental scan. Never claim otherwise.

**Graphify:**

- Use only code-only/offline extraction. Never run bare `graphify extract`
  (no `--code-only`) if the corpus has any doc/paper/image files and no
  backend key is configured — it will either hard-fail (no key) or, if a
  key happens to be set, dispatch to an external LLM. Code-only avoids both.
- Never automatically install hooks (`graphify hook install`,
  `<platform> install`) or wire an always-on integration as a side effect
  of an unrelated task.
- Never use `--neo4j-push`/`--falkordb-push`/`--mcp` or any external
  graph/database backend.
- Check `graphify --help` / `graphify extract --help` before using an
  update-style flag — command syntax can differ across Graphify versions;
  do not assume a flag from memory still applies.
- Verified cold-build commands for the installed version (0.9.18):

  ```bash
  graphify extract . --code-only
  graphify cluster-only . --no-label --no-viz
  ```

- Scoped local queries (no network, no LLM):

  ```bash
  graphify query "question"
  graphify path "A" "B"
  graphify explain "node"
  ```

- If `graphify-out/` is stale and a safe incremental command cannot be
  verified against the installed version's actual `--help` output, rerun
  the verified cold-build commands above rather than inventing an
  `--update` invocation that may not exist or may behave differently.

## Before changing code

Require, and state explicitly in the plan:

- affected resource list
- event/export/callback contracts involved
- database tables touched
- permissions and ownership boundaries crossed
- client/server/NUI context of each change
- backward-compatibility risks
- migration requirements
- manual gameplay-test requirements

## During changes

Require:

- the smallest coherent change that satisfies the request
- server authority (never trust client-supplied state)
- fail-closed validation
- compatibility with existing contracts (event names, export signatures,
  NUI callback names, table schemas) unless the change is explicitly a
  breaking migration
- no unrelated cleanup or opportunistic refactors
- no replacement of persistent IDs (character ID, vehicle ID, house ID)
  with transient/session IDs
- no debug spam left behind
- no secret exposure in code, logs, or reports
- no unapproved production deployment

Refer to `references/security-review.md` for privileged/network/database
operations, and `references/intelligence-workflow.md` for map usage and
interpretation.

## After changes

Require, in order:

1. Review the diff.
2. Run applicable syntax/build/test checks for the languages touched.
3. Refresh the CM contract map.
4. Compare newly unresolved/missing contracts against the pre-change map.
5. Refresh Graphify only when generic call relationships materially
   changed (not for every trivial edit).
6. Check security boundaries relevant to the change
   (`references/security-review.md`).
7. Confirm unrelated working-tree changes were preserved untouched.
8. Provide manual FiveM runtime test steps — static checks never prove
   runtime behavior.
9. Report remaining risks and anything left unverified.

See `references/validation-matrix.md` for change-type-specific checks.

## Diagnosis/review/change/release boundary

- **Diagnose**: determine cause and cite evidence (files, contracts,
  queries run). Do not implement a fix unless asked.
- **Review**: report findings first. Do not silently edit code while
  reviewing it.
- **Change**: implement, validate per the matrix, and report.
- **Release**: prepare artifacts/checks but do not deploy live without
  explicit user approval.

## Required completion report

Every non-trivial task ends with:

- result
- changed files
- affected resources/contracts
- validation performed
- validation not possible (and why)
- security considerations
- database/migration instructions (if any)
- manual FiveM tests to run
- remaining risks
- confirmation that unrelated work was preserved
