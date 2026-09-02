# CM FiveM Autopilot

A persistent outer supervisor for Codex CLI. It plans first, requests one human approval, then launches discrete execution and repair cycles until final review reports the approved goal complete or blocked.

## Start

From the repository root:

```powershell
.\tools\cm-autopilot\run.ps1
```

The runner uses the existing Codex CLI authentication. It never stores API credentials. You can also launch the VS Code task `CM: FiveM Autopilot`.

For non-interactive shells, `-PlanOnly -Goal "..."` runs the planning cycle and stops at the approval boundary. A normal subsequent run displays the saved plan and asks for approval.

## Workflow

1. Enter a goal. The runner initializes `agent-docs/autopilot/` without editing gameplay.
2. A planning-only Codex cycle audits the repository and writes a plan with `status = pending_approval`.
3. Approve, cancel, or revise the goal/plan. Approval is requested once.
4. The runner invokes `codex exec` repeatedly. Each prompt contains repository rules, master/phase prompts, all persistent state, current Git status, and the previous result.
5. After static validation, execution uses `tools/cm-runtime/runtime-controller.ps1` to start or reuse the local txAdmin server, review only the current console window, restart the smallest changed resource, and feed code-level failures into the next repair cycle (up to `maxRepairAttempts`).
6. A final review either reopens execution, blocks for required evidence, or completes the goal and writes next ideas without implementing them.

`maxCycles: 0` means unlimited cycles until complete or blocked. `autoPush` is safety-enforced as `false`. Checkpoint commits are disabled by default and still require the agent to meet the master prompt's isolation and validation rules.

## Resume and stop

An unfinished state is detected on startup and can be resumed. Press Ctrl+C to stop safely after the current process handles interruption. To prevent another cycle from launching, create an empty `tools/cm-autopilot/STOP` file; remove it before resuming.

## Audit-only test

This checks configuration, files, Git access, prompt assembly, and Codex CLI availability without invoking Codex or changing persistent state:

```powershell
.\tools\cm-autopilot\run.ps1 -DryRun -Goal "Audit-only test goal"
```

## Logs and safety

Each cycle writes under `tools/cm-autopilot/logs/YYYY-MM-DD/cycle-NNNN-phase/`: the redacted prompt, before/after changed-file lists, Codex output, last message, and exit code. State documents carry plan items, validation, repair attempts, blockers, and runtime tests. Common credential patterns are redacted, and prompts prohibit reading or logging protected paths.

The runner does not push, deploy, reset, clean, or touch gameplay on its own. The Codex cycles use `--approve-for-me`, which routes routine approvals through automatic review under the workspace-write sandbox. Destructive data changes, secrets, paid/private assets, major deletions, ambiguous product decisions, merge conflicts, and required runtime evidence remain human boundaries.

Local runtime setup and commands are documented in `tools/cm-runtime/README.md`. Runtime state and sanitized error blocks live under `agent-docs/runtime/`; raw txAdmin logs remain outside the repository.
