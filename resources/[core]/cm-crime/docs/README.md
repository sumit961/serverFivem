# cm-crime: shared criminal-session framework (v1.0)

`cm-crime` is **infrastructure** for crime content. It owns a generic activity registry and the lifecycle of one criminal attempt
(session): site lock, cooldowns, police requirement, participants, stages, dispatch trigger, terminal resolution, a **one-time reward
authorization**, recovery and an audit trail. It is not a robbery.

It creates **$0, 0 items and 0 XP**, and owns no inventory, weapons, banking, evidence, police roster, dispatch, gang/family state, minigame, UI or loot table.
There is **no client surface** (no net event, NUI callback, command or manifest client script): content resources call it server-to-server.

```
CLIENT -> crime content server resource (physical checks, minigame, tool use) -> cm-crime exports -> cm-law dispatch / own tables
```

## Classification and audit

**NEW RESOURCE `cm-crime`.** Audit result:

| Area | Finding |
|---|---|
| Generic crime / session framework | none |
| Robbery systems | `cm-gang` has a legacy *player* robbery seam (`server/robbery.lua`, `cm-inventory/server/robbery.lua`), `cm-law` has an `armed_robbery` charge and logistics `robbery_state`. None is a session framework; not touched. |
| Police count | `cm-law:GetOnDutyCount(orgId)` (authoritative, read-only; **RESOLVED 2026-10-03**, see `cm-law/docs/ON_DUTY_COUNT.md`). |
| Dispatch | `cm-law:CreateLawIncident(details, coords, callerCid, callerName, options)` is a safe server export (used by the embedded police resource too). **Used as is.** |
| Evidence | no generic evidence platform; not built (future contract below). |
| Inventory / tools | `cm-inventory` already exports `HasItem`, `RemoveItem`, `HasItemDurability`, `ConsumeItemDurability`. cm-crime does not call them: the content owner does. |
| Weapons | `cm-weapons` / `cm-inventory` equipped-weapon state; not needed by the framework. |
| Rewards | `cm-playerdata` `AddMoneyToCharacter`, `cm-inventory` `AddItemToCharacter`. No dirty-money concept exists, so none is invented. |
| Admin/audit | `cm-admin` `AddLog` / `cm-admin:server:addLog`; used for terminal outcomes and admin actions. |

## Registry (who may register)

`Config.TrustedOwners` is an allowlist of **resource names** checked with `GetInvokingResource()`. It ships empty (fail closed): the reviewed content resource is added by name.
A definition is bound to its registering resource: the same owner may re-register (restart / hot reload) and replaces its own definition; another resource using the same id gets `owner_mismatch`.
Every session records `owner_resource`, and **every mutation checks the invoker against it**: one crime resource cannot join, advance, dispatch, complete, fail, cancel or confirm another's session.

Definition fields (all bounded by `Config.Limits`; omitted fields use `Config.Defaults`):

| Field | Meaning |
|---|---|
| `id` (`^[a-z0-9_]{3,40}$`), `label`, `category` | identity and display |
| `minPolice`, `policeOrg` | minimum on-duty law members of that organization |
| `participants = {min,max}`, `allowJoin` | group size; may characters join after activation |
| `sessionSeconds` (60-7200) | maximum duration; the sweep expires stale sessions |
| `siteMode` | `exclusive` (one active session per site key) or `none` |
| `busyGroup` | one active session per character **per group** (default `high_value`); different groups may coexist |
| `cooldowns = { site, activity, character, onFailure = full|partial|none, partialFactor }` | seconds; which scopes apply is per activity |
| `dispatch = { mode = none|immediate|delayed|chance|stage, types = {key = text}, delaySeconds, chance, stages, priority }` | server-side policy; `types` maps an allowed key to server-defined text |
| `stages`, `strictOrder` | optional stage list (names are the content's); strict = no skipping |
| `reward = { enabled }` | whether a success issues a reward authorization |
| `policy = { onInitiatorLeave = continue|fail, disconnectGraceSeconds, onOwnerStop = fail|cancel, ownerStopGraceSeconds }` | failure / recovery policy |

Required-item and weapon policies are deliberately **not** framework features: the content owner asks `cm-inventory` / `cm-weapons` before it calls `BeginCrimeSession`.

## Session model

```
created --(first AdvanceCrimeStage)--> active --> succeeded | failed | cancelled | expired
created --> failed | cancelled | expired
```

* `BeginCrimeSession` validates, in order: owner pin, site-key format, participants (character ids, count, online, same routing bucket), character/activity/site cooldowns,
  site occupied, character busy, police requirement; then inserts the session (UNIQUE `active_site`) and participants (UNIQUE `active_key = character:busyGroup`). If another start wins a character in the gap,
  the new session is rolled back (`cancelled`, `start_failed`, no cooldown).
* **Site lock**: the **owner supplies a configured site key** (`store:24`, `atm:901`); client coordinates are never the authority. Held from creation until a terminal state; rebuilt from the database after a restart.
* **Participants** are character ids (`leader` + `member`). Join is idempotent, bounded by `max`, requires an online character in the session's routing bucket who is not busy and not on cooldown. `LeaveCrimeSession(ref, cid, 'left'|'failed', reason)`
  records leaving/incapacitation; the last participant leaving fails the session; the initiator leaving fails it only if the activity says so.
* **Stages**: `AdvanceCrimeStage(ref, expected, next, ctx)` is a compare-and-swap on the current stage; a replay of the same transition returns `replayed`. With a declared list, unknown stages are rejected and `strictOrder` forbids skips.
  `ctx.characterId` (optional) must be an active participant in the session's routing bucket. cm-crime does **not** verify gameplay facts (proximity, minigame, drilling time): the content owner does.
* **Timeout / recovery**: every session has `expires_at`. The sweep (10 s and at start) expires stale sessions, removes participants offline past the grace, fails/cancels sessions whose owner resource stopped or never re-registered (after the owner grace),
  retries pending dispatch and flags unconfirmed rewards. State is database-authoritative, so restart changes nothing but recomputation.

## Police requirement

`def.minPolice` is checked at start. The count comes **only from cm-law**: `exports['cm-law']:GetOnDutyCount(policeOrg)` (default org `police`; any law organization id works, e.g. `sahp`, `sheriff`).
It returns a number (members of that organization who are on duty, ranked, not suspended and currently loaded) or `nil, reason`. cm-crime applies the activity's own requirement:

| Situation | Result |
|---|---|
| `minPolice <= 0` | allowed; law is not contacted |
| count `< minPolice` (including a healthy `0`) | `not_enough_police` |
| count `>= minPolice` | allowed |
| cm-law stopped, not ready, caller forbidden, invalid org, error, or a malformed/non-numeric/negative answer | `police_unavailable` (fail closed) |

There is **no fallback** and no per-character enumeration: the old `IsOnDuty` loop was removed. Only successful counts are cached (`Config.Police.cacheSeconds`, 5 s); failures are never cached, so after a cm-law restart
the count resumes by itself with no cm-crime restart. There is no police table in cm-crime.

> **RESOLVED (2026-10-03)**: the former `SHARED INTEGRATION REQUIRED - cm-law: GetOnDutyCount(orgId)` blocker is implemented in cm-law (`server/duty_count.lua`, docs `cm-law/docs/ON_DUTY_COUNT.md`).

## Dispatch

`TriggerCrimeDispatch(ref, type)` validates the session (active, owner, allowed `type` key, session cap 5, stage policy), then applies the activity policy **server-side**: `immediate`, `delayed` (stored `dispatch_at`, sent by the sweep),
`chance` (server roll), `stage` (only in configured stages). Once per type per session (unique journal key), so duplicates and races send once. It calls the existing `cm-law:CreateLawIncident` with only: server-built text
(`<site label>: <type text>`), the **configured** session coordinates, category, priority, `callType = 'crime_alarm'`, organization `police`, and the session's routing bucket. No participants, no character ids. If law is unavailable the dispatch stays `pending`
and is retried (30 s steps, 5 attempts) then marked `failed`; the caller cannot suppress it. `ctx.coords` come from the owner at `BeginCrimeSession` (configured site), never from a client.
Law integration: **COMPLETE** (no law change needed).

## Cooldowns

Stored in `cm_crime_cooldowns`, UNIQUE `(scope, scope_key, activity_id)`, server epoch seconds, so they survive reconnect, resource restart and server restart. Applied when a session ends:
`succeeded` = full; `failed`/`expired` = per `onFailure` (`full`, `partial` x `partialFactor`, `none`); `cancelled` = none. Scopes: **site** (site key), **activity** (activity id), **character** (each participant, per activity). Setting never shortens a longer existing cooldown.
`GetCrimeCooldown(activityId, scope, key)` reads remaining seconds (owner of the activity only).

## Reward authorization (no minting)

`CompleteCrime(ref, result)` is the **only** success path. One guarded `UPDATE ... WHERE status IN ('created','active')` picks the single terminal winner (complete/fail/cancel/expire race), and on success sets `reward_state = pending` and generates **one** `reward_token`
in that same update, with a once-only `reward_authorized` journal event. `result` may only contain `tier` / `note` (short `[A-Za-z0-9_ -]` strings); any money/items/XP/other key is rejected (`invalid_result`). Replays return the **same** token and the current `rewardState`.

The owner then applies its configured proceeds through the authoritative owner (`cm-playerdata`, `cm-inventory`, ...), idempotently, and calls `ConfirmCrimeReward(ref, token)` -> `delivered` (once; replays are no-ops) or
`ReportCrimeRewardFailure(ref, token, reason)` -> `failed` (reconciliation). A `pending` reward that is never confirmed is flagged `failed` by the sweep after 15 min (event `reconciliation`, never auto-delivered, never re-issued).
`AdminReconcileCrime(ref, 'delivered'|'failed')` resolves it by hand. The token is never shown in the admin inspect view.

## Economy

The framework generates **$0, 0 items, 0 XP** and has no code path to money/items/XP. Content must price risk against the economy standard (`agent-docs/CM_ECONOMY_STANDARD.md` s.5/7: time, failure probability, police response, tool cost,
cooldown, difficulty, item sinks) and avoid "crime = top payout by default". No dirty-money concept exists in cm-playerdata/cm-bank/cm-items, so none is created; laundering and illegal-proceeds items are future platform work.

## Database (additive, idempotent, applied at start)

| Table | Purpose / keys |
|---|---|
| `cm_crime_sessions` | `reference` UNIQUE, `active_site` UNIQUE (site lock), `idem_key` UNIQUE, status, leader, stage/prev_stage, bucket, configured coords/label, dispatch state/pending, reward_state/token, timestamps; indexes (status, expires_at), (owner, status), (reward_state, completed_at) |
| `cm_crime_participants` | UNIQUE (session_ref, character_id), `active_key` UNIQUE (`character:group`, NULL when inactive) |
| `cm_crime_cooldowns` | UNIQUE (scope, scope_key, activity_id), expires_at, reason, session_ref |
| `cm_crime_events` | append-only; `journal_key` UNIQUE for once-only events (`<session>:terminal`, `:reward_authorized`, `:dispatch:<type>`, `:cooldown:*`, join/leave) |

No FiveM source id and no account identifier is stored. Reward state lives on the session row (no separate reward table). Event kinds: `session_created`, `participant_added/removed`, `session_active`, `stage_advanced`, `dispatch_requested/triggered/suppressed/pending/failed`,
`session_succeeded/failed/cancelled/expired`, `reward_authorized/delivered/failed`, `cooldown_applied`, `reconciliation`, `admin_cancel`.

## Public API (server exports; caller = the activity owner unless noted)

`RegisterCrimeActivity(def)`, `CanBeginCrime(activityId, ctx)` (read-only "can this start?"), `BeginCrimeSession(activityId, ctx)`, `JoinCrimeSession(ref, cid)`, `LeaveCrimeSession(ref, cid, state, reason)`, `GetCrimeSession(ref)`,
`AdvanceCrimeStage(ref, expected, next, ctx)`, `TriggerCrimeDispatch(ref, type)`, `CompleteCrime(ref, result)`, `FailCrime(ref, reason)`, `CancelCrime(ref, reason)`, `ConfirmCrimeReward(ref, token)`,
`ReportCrimeRewardFailure(ref, token, reason)`, `GetCrimeCooldown(activityId, scope, key)`.
Admin (caller must be `cm-admin`): `AdminListCrimeSessions`, `AdminInspectCrime`, `AdminListCrimeCooldowns`, `AdminCancelCrime`, `AdminReconcileCrime`. Console: `cm_crime_list|inspect|cooldowns|cancel|reconcile`.
Local server event for content resources to re-register: `cm-crime:server:registryReady` (not networked). All return `true, data` or `false, reason`.

`BeginCrimeSession` ctx: `siteKey` (`type:id`), `leaderCharacterId`, `participantCharacterIds`, `siteLabel`, `coords {x,y,z}` (configured site, used for dispatch), `metadata` (<= 1 KB), `idempotencyKey`.

## Consumer guide (Agent 3 / Agent 4)

```lua
-- 1. register (start + registryReady). Add the resource name to cm-crime Config.TrustedOwners first.
local function register()
    exports['cm-crime']:RegisterCrimeActivity({
        id = 'store_robbery', label = 'Store Robbery', category = 'retail', minPolice = 2,
        participants = { min = 1, max = 3 }, sessionSeconds = 900, busyGroup = 'high_value',
        cooldowns = { site = 3600, character = 1800, onFailure = 'partial' },
        dispatch = { mode = 'immediate', types = { alarm = 'Silent alarm triggered' }, priority = 2 },
        stages = { 'approach', 'register', 'safe', 'escape' }, strictOrder = true,
    })
end
AddEventHandler('onResourceStart', function(r) if r == GetCurrentResourceName() then register() end end)
AddEventHandler('cm-crime:server:registryReady', register)

-- 2. client asked to start; YOU validate location/tool (cm-inventory:HasItem), then ask the framework
RegisterNetEvent('cm-store-robbery:server:start', function(storeId)
    local cid = tostring(exports['cm-playerdata']:GetCharacterId(source))
    local site = Config.Stores[storeId]; if not site then return end                  -- server-known site, never client coordinates
    local ok, s = exports['cm-crime']:BeginCrimeSession('store_robbery', { siteKey = 'store:' .. storeId, leaderCharacterId = cid,
        siteLabel = site.label, coords = site.coords })
    if not ok then return notify(source, s) end                                       -- site_occupied / not_enough_police / ...
    sessions[cid] = s.reference
end)

-- 3. gameplay (you verify proximity/minigame), then advance
exports['cm-crime']:AdvanceCrimeStage(ref, 'approach', 'register', { characterId = cid })
-- 4. dispatch (server-side policy decides if/when it is sent)
exports['cm-crime']:TriggerCrimeDispatch(ref, 'alarm')
-- 5. finish
local ok, r = exports['cm-crime']:CompleteCrime(ref, { tier = 'standard' })           -- or FailCrime(ref, 'caught')
-- 6. consume the ONE authorization: pay through the economy owner, idempotently, then confirm
if ok and r.rewardState == 'pending' then
    local paid = exports['cm-playerdata']:AddMoneyToCharacter(cid, 'cash', Config.Payout.standard, 'store_robbery:' .. ref)  -- your priced, reviewed payout
    if paid then exports['cm-crime']:ConfirmCrimeReward(ref, r.rewardToken)
    else exports['cm-crime']:ReportCrimeRewardFailure(ref, r.rewardToken, 'economy_failed') end
end                                                                                    -- repeated CompleteCrime returns the same token: never pay twice
```

## Evidence (future contract, not built)

Law owns evidence. Content may later call a supported law/security evidence API for fingerprint, shell casing, tool-mark or camera opportunities. cm-crime only exposes the session reference and site key as the correlation id.

## Boundaries, shared integrations and tracked blockers

| Owner | Status |
|---|---|
| cm-law | dispatch **COMPLETE** (existing `CreateLawIncident`); police count **COMPLETE** (`GetOnDutyCount`, authoritative, no fallback) |
| cm-inventory | **NOT REQUIRED** by the framework (safe `HasItem`/`RemoveItem` exist for content owners) |
| cm-items | **NOT REQUIRED** (future content validates its loot against cm-items) |
| cm-weapons | **NOT REQUIRED** |
| cm-admin | exports ready; UI wiring **SHARED INTEGRATION REQUIRED** (deferred) |
| cm-gang / cm-family | not modified; optional future eligibility is the content owner's call to their public APIs |

Unresolved mechanic-task blockers (unchanged, not fixed here): `cm-vehicles:ServiceVehicle` has no trusted-caller validation; `cm-tuning` has no mechanic/business gate; `cm-billing` has no generic refund API; mechanic admin UI is deferred.

## Tests

`lua tests/selftest.lua` (deterministic, no FiveM/DB): real cm-crime core + config over a fake store that mirrors the SQL CAS / UNIQUE semantics; characters, law police-count and law dispatch are labelled doubles. `test_small_crime`
exists only in the test. The real SQL store has not been run against MySQL. Not run by design: any FiveM runtime or gameplay.
