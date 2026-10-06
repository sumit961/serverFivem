# `GetOnDutyCount(orgId)` — authoritative on-duty count

Read-only server export of **cm-law** (v3.5.6+). Law owns organizations, membership and duty; consumers ask, they never keep a roster. First consumer: `cm-crime` (`minPolice`).
Implementation: `server/duty_count.lua` (pure factory) wired next to `IsOnDuty` in `server/main.lua`. cm-law knows nothing about crime policy.

```lua
local n, reason = exports['cm-law']:GetOnDutyCount('police')   -- number, or false + reason; ids: 'police', 'sahp', 'sheriff', 'fib', 'army', any future Config.Organizations id
```

| Return | Meaning |
|---|---|
| `n` (integer >= 0) | law is healthy; `n` eligible members are on duty. **`0` is a real answer.** |
| `false, 'unavailable'` | law cannot answer authoritatively (central law or embedded police not ready, database error). Never treated as 0. |
| `false, 'invalid_organization'` | `orgId` is not a string id of a law organization (central `Config.Organizations` or the embedded legacy `police`). |
| `false, 'forbidden'` | the invoking resource is not in `Config.OnDutyCountCallers`. |

## Who is counted

A character is counted once per requested organization when **all** hold: it has a member row **of that organization** with an existing rank; its persisted `on_duty` flag is set; it is **not suspended**
(central: any `suspended_until`; legacy `police`: a future `suspended_until`); and it is **currently loaded on a connected player** (`sourceFor(characterId)` resolves and `GetPlayerName` answers).
Law ends duty on disconnect, character unload and death; the loaded-character filter additionally ignores stale `on_duty = 1` rows left by a crash or a law restart until that character is loaded again.
Not counted: off-duty or suspended members, other organizations (a character in two organizations counts once in each), civilians, EMS, gang/family members, admins who only hold permissions, anyone without a member row.
Identity is the Character ID; FiveM source is used only to prove the character is online. The result is a bare number (no names, ids, ranks or positions).

## Organizations

Central organizations come from `Config.Organizations` (today `sahp`, `sheriff`, `fib`, `army`); a new law organization works with no code change. The embedded legacy organization is `police` (its own tables; `validOrgId('police')` is intentionally
nil in the central helpers, so the count has an explicit `police` branch). Ids are normalized (trim, lower-case, `[a-z0-9_]`, <= 32).

## Performance

One small indexed query per call (`cm_legal_members` primary key `(organization_id, character_id)`; the legacy table is keyed by character), then one `sourceFor` per on-duty row (a handful). No in-memory roster exists to reuse and none was added.
`cm-crime` caches a successful answer for 5 s and never caches a failure.

## Security

Failures are `false, reason` (never `nil, reason`: FiveM drops the values after a leading nil, so the reason would be lost). Consumers must treat anything that is not a number as unavailable.

Server-to-server only: there is no net event, callback or command for the count. Callers are allowlisted by `GetInvokingResource()` in `Config.OnDutyCountCallers` (`cm-crime`, `cm-admin`, `cm-law`); add a resource name there to grant read access.

## Restart behaviour

While `cm-law` is stopped or not ready every consumer gets `false` (or `GetResourceState` refuses the call) and fails closed; once law is ready again the next call answers and consumers recover with no restart.

Tests: `lua tests/duty_count_selftest.lua` (33), `python tests/duty_count_mysql_smoke.py` (7, scratch database), `cm-crime/tests/law_count_integration.lua` (26).
