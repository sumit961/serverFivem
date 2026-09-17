# DECISIONS

## Cycle 30 final review decision

- No source plan item is reopened: final diff/source, fixed schema, manifests,
  gang contracts, state artifacts and introduced TODO/FIXME markers revealed
  no fixable static defect.
- Do not set the goal to `complete`. The approved plan makes the full GATE-V4
  FXServer/OneSync/NUI/disposable-database suite an explicit acceptance
  condition, and no actual results are recorded. Set `STATE.json` to `blocked`
  and retain the exact reproduction and expected-result matrix in
  `RUNTIME_TESTS.md`/`BLOCKED.md`.
- Do not write a final `COMPLETED.md` summary or generate the 3-5 final
  `NEXT_IDEAS.md` proposals until runtime evidence permits a later review to
  declare genuine completion.
- Static evidence for this decision: validator 0 errors with 3 pre-existing
  warnings; scanner current; 15 Lua and 2 JavaScript syntax checks passed;
  manifest references present; `git diff --check` passed with line-ending
  notices only.

## Cycle 29 invite decline race repair decisions

- Use one conditional `UPDATE` as the decline linearization point. It requires
  the invite ID, target character ID, pending status and a future expiry, then
  treats an affected-row count other than one as a losing/expired response.
- Write `invite_declined` activity and notify success only after that update
  changes exactly one row. This makes decline mutually exclusive with the
  periodic expiry worker and competing Accept/Decline responses without a
  schema or public contract change.
- Keep the per-target response lock as local spam/concurrency protection while
  relying on the database condition for correctness across expiry-worker and
  database races. Boundary behavior still requires the recorded disposable
  database/FXServer test.

## Cycle 28 final review decision

- Reopen `GANG-004` because the invitation Decline branch does not inspect the
  affected-row result of its conditional `status = 'pending'` update. The
  periodic expiry worker can change the row after the initial validity read;
  the decline update then affects zero rows, but the current code still writes
  `invite_declined` activity and reports a successful decline.
- The execution repair must consume a pending, unexpired invite exactly once
  before logging/notifying decline, and preserve one truthful terminal status
  under decline/expiry and simultaneous response races. Keep the public event
  and schema compatible unless source evidence requires otherwise.
- Static gates passed: validator 0 errors with 3 pre-existing warnings, current
  CM scanner output, 13 `cm-gang` Lua files and 2 JavaScript files syntactically
  valid, manifest paths present, and `git diff --check` clean apart from line
  ending notices. Runtime acceptance remains required after the repair.

## Cycle 26 invite expiry race repair decisions

- Consume the invite before creating membership and use MySQL `ROW_COUNT()` in
  the immediately following transaction statement as the fail-closed gate.
  InnoDB row serialization makes expiry and acceptance mutually exclusive:
  only the update that observes `pending` and unexpired can affect one row.
- Keep the existing transaction API and schema. A new migration, stored
  procedure or public contract is unnecessary for this repair.
- Verify the accepted invite/member relationship after commit before refreshing
  state, logging `member_joined` or notifying success. This protects the caller
  from a transaction wrapper that reports successful execution when the gated
  insert intentionally affected zero rows.
- Retain the one-character/one-gang unique constraint as the final concurrent
  membership backstop. Expiry-boundary and simultaneous Accept/Decline remain
  explicit disposable-database runtime tests rather than static claims.

## Cycle 23 final review decision

- Reopen `GANG-004` because invite acceptance does not atomically prove that
  the invite remained pending and unexpired when membership was inserted. The
  current transaction can report success even when its conditional invite
  `UPDATE` affects zero rows, allowing the periodic expiry worker to win the
  race while the membership insert still commits.
- The execution repair must make invite consumption and membership insertion
  one fail-closed atomic decision, preserve the unique one-gang constraint,
  and validate accept-at-expiry plus simultaneous response behavior. No
  gameplay code was changed during this review cycle.

## Cycle 22 armory lock repair decisions

- Track each armory lock's persistent character ID and current transport source
  separately from the lock flag. This permits bounded disconnect cleanup
  without parsing the composite lock key or depending on playerdata still being
  loaded after `playerDropped`.
- Protect the complete database/inventory checkout section with `xpcall`, then
  release lock state in one unconditional post-call path. If an exception occurs
  after journaling but before delivery, attempt to void that issued row before
  returning a generic failure.
- Once inventory delivery succeeds, do not turn an activity-log exception into
  a retryable checkout failure. Report the controlled server-side logging error
  and return success so a client retry cannot duplicate a delivered item.
- The repair changes no public event, callback, export, schema or permission
  contract. Runtime exception and disconnect timing remains in the manual
  FXServer suite rather than being inferred from static validation.

## Cycle 20 final review decision

- Reopen `GANG-008` because `cm-gang/server/storage.lua` can retain an
  armory checkout lock after an exception, and its disconnect handler clears
  only cooldown state. This violates the approved failure/disconnect cleanup
  requirement and is fixable statically. The execution cycle must add
  guaranteed cleanup and validate success, ordinary failure, thrown-error,
  disconnect and resource-stop paths before final review resumes.
- Do not finalize `COMPLETED.md` or generate `NEXT_IDEAS.md` in this review;
  those final artifacts remain gated on the repaired implementation passing
  review.

## Cycle 18 final review decisions

- Do not make speculative runtime changes after the static security and
  contract review passed. OneSync entity lifecycle, NUI behavior and real
  transaction concurrency remain explicit manual tests.
- Keep optional owner integrations soft and guarded. `cm-gang` owns policy;
  inventory, items, weapons, vehicles, vehicle keys, catalog, chat and admin
  retain their existing authority without a new hard dependency cycle.
- Treat the three validator warnings as pre-existing repository debt: two
  missing `map4all-pillbox` paths and a potentially stale resource registry.
  They are unrelated to the gang implementation and were not hidden or edited.
- Move the approved goal to `review_ready`, not runtime-complete. Static checks
  cannot satisfy the recorded FXServer/OneSync/NUI/database suite.
- Apply one evidence-backed final repair: fleet return uses the same operation
  lock family as fleet call, plus a distinct return throttle. Keep the lock
  around recall, key revocation, persistence transition and activity logging so
  concurrent callbacks cannot complete the same logical return twice.

## Cycle 15 administration decisions

- Keep gangs out of the generic legal-organization registry and policy. The
  dedicated page preserves gang membership independence from Police, EMS,
  legal organizations and family membership.
- Require `gang.admin.view` for read payloads and `gang.admin.manage` for every
  mutation. `cm-gang` independently verifies the invoking resource is
  `cm-admin`, so a different resource cannot reuse privileged exports.
- Accept only code-owned local asset keys, fixed gang/facility IDs,
  `cm-weapons` catalog IDs and `rn-vehicleshop` models. Location writes read the
  admin's server entity, heading and routing bucket rather than NUI coordinates.
- Keep leader removal non-destructive: demote the leader to the highest
  non-leader rank and expose the vacancy. Replacement is an explicit
  transaction and never alters family or job memberships.
- Limit recovery to safe stale-invite expiry and authoritative cache reload in
  this cycle. No broad delete/reset/data-rewrite operation is exposed.
- A successful identity, leader or rank mutation must reload the complete
  database-backed gang domain before reporting success. Refreshing selected
  state bags alone cannot update cached gang identity, rank or membership
  authority.

## Cycle 14 fleet decisions

- Store one gang fleet authorization row per fixed gang/catalog model, while
  `cm_owned_vehicles.id` remains the physical and persistent `vehicle_id`.
- Route gang organization ownership through `cm-vehicles`' existing trusted
  organization seam for only `gang_1` through `gang_4`; all access is resolved
  back through `cm-gang:GetVehicleAccessDecision` on every vehicle action.
- Pair current server-authoritative organization access with a revocable
  session-key record. Each use delegates to `cm-gang`; membership/rank/
  permission/enabled changes fail closed and remove the record. It is neither
  personal ownership nor a permanent/lent key.
- Do not repair or refuel gang vehicles on call/return. The legal-fleet service
  policy is domain-specific and would violate preservation of genuine damage.
- Require `cm-admin` as the invoking resource for permanent placement and fleet
  configuration. GANG-010 supplies the corresponding admin permission/UI.
- The scanner reports dynamic target names for calls through the code-owned
  `VEHICLES`/`SHOP` constants; direct source verification confirmed those
  constants resolve only to `cm-vehicles` and `rn-vehicleshop`.

## Cycle 12 stash/armory decisions

- Keep external-storage mutation in `cm-inventory` and add a generic
  invoking-resource validator/audit export contract, avoiding a hard
  `cm-inventory` dependency on `cm-gang`.
- Identify shared stashes as `owner_type=gang_stash` and
  `owner_id=<fixed gang id>`; revalidate owner authority on every movement.
- Resolve armory items only from enabled `cm-weapons` weapon/ammunition rows.
  Clients submit an item ID only; quantity, tier, limits and metadata are
  server-owned.
- Journal an armory issue before inventory delivery and mark it void on safe
  delivery failure. Serialize per-character/item checkout so concurrent limit
  checks cannot issue twice through the gang path.
- Gang issues are not duty equipment and are not reclaimed on duty changes;
  they never invoke legal firearms-license checks.

## Cycle 11 chat/dashboard/NPC decisions

- Route both `/g` and the CM Chat GANG tab through `cm-gang:SendGangChat`; CM
  Chat is presentation/log authority and rebuilds recipients from `cmGang`.
- Keep membership/permissions out of client authority. Dashboard data is
  assembled per request, and member mutations reuse GANG-003 owner exports.
- Use the existing facility table for headquarters and a code-owned NPC model
  allowlist. Wrong-bucket, disabled, incomplete or unknown-model HQ rows fail
  closed and do not spawn a ped.
- Expose armory/stash/fleet tabs as configured availability only until their
  owner integrations land in GANG-008/009; do not create placeholder mutations.

## Cycle 10 item robbery decisions

- Keep physical authorization in `cm-gang`, protection definitions in
  `cm-items`, and exact-row visibility/mutation in `cm-inventory`.
- Expose single-use opaque tokens instead of row IDs or metadata.
- Protect only verified physical identity items by default; ordinary items
  remain stealable unless their definition sets `robberyProtected = true`.
- Preserve unique weapon/serial/durability metadata from the stored row and use
  inventory's existing stack-equivalence rules.
- Deny equipped-bag theft when removal would invalidate slots or capacity.
- Use atomic multi-row mutation or conditional insert-from-source; never
  compose Remove+Add/refund for robbery.

## Cycle 9 robbery decisions

- Accept only server-observable cuffed (`cmCuffed`) or `cm-playerdata` dead
  state. A client-only hands-up flag is not accepted or introduced.
- Centralize the physical/permission/state decision in a server-only gang
  export so item search and transfer can reuse the exact GANG-005 boundary.
- Keep the amount client-selectable but bounded; resolve and mutate actual cash
  in `cm-playerdata`. Bank is outside this contract and is never touched.
- Replace debit/credit/refund composition for robbery with one conditional SQL
  update over both character rows. Live player money mutations are locked while
  their balances are prepared and committed, and stale DB balances fail closed.
- Permit only `cm-gang` to call the new cash-only atomic owner export. General
  player-to-player money behavior remains unchanged.

## Cycle 8 invitation decisions

- Keep permission maps out of replicated `cmGang` state. G-menu target changes
  call a narrow server callback that returns only whether Invite should be
  visible for that actor/target pair; the actual action remains independently
  authoritative.
- Re-check routing bucket and the stricter gang interaction distance inside
  `cm-gang`. The reusable `cm-playerdata` extension bridge validates online
  state and distance but currently does not enforce routing-bucket equality.
- Select the current lowest non-leader database rank both when creating and
  accepting an invite. Clients never submit gang or rank authority, and a rank
  configuration change invalidates the stale invitation rather than silently
  assigning a different rank.
- Cancel pending invitations involving a disconnected actor or target. This
  deliberately prefers fail-closed local interaction semantics over allowing
  an invite to become an offline/remote recruitment path.
- Use the schema's unique pending-target slot, a per-target response lock and a
  membership transaction. One character can have only one pending gang invite
  and one gang membership even under repeated client requests.

## Cycle 7 owner-domain decisions

- Keep all GANG-003 mutation APIs server-only exports. Client events and NUI
  callbacks are introduced only with their feature-specific guards in later
  plan items, so a partially built client surface cannot mutate membership.
- Treat stored rank permission JSON as authoritative but filter it through the
  fixed `Config.Permissions` catalog on load and write. Unknown keys never grant
  authority.
- Replicate only gang display identity and rank presentation through `cmGang`.
  Character IDs and permission maps remain server-side.
- Serialize mutations per gang and re-resolve actor authority inside the lock.
  This prevents two normal owner API calls from concurrently bypassing rank or
  leader hierarchy decisions.
- Do not auto-reassign members when deleting a rank. An in-use rank fails
  closed, preserving explicit database-authoritative membership choices.
- Restrict normal leadership replacement to the current leader and an existing
  same-gang target. Broken/leaderless recovery remains an explicit logged
  `cm-admin` workflow under GANG-010.

## Cycle 6 schema decisions

- Persist gang identity as the immutable string key `gang_1` through `gang_4`; display name/tag/color/assets remain editable database fields. A database CHECK and startup validation reject any fifth/missing/relabelled slot.
- Seed gangs disabled and without a fabricated leader character. One leader rank is seeded, while actual leader membership is assigned later through the serialized GANG-003/admin recovery contract.
- Seed initial ranks only when that gang has no ranks. This preserves all post-install rank names, tiers and permissions on migration reruns.
- Use composite gang/rank foreign keys so a member or invitation cannot reference another gang's rank. Use generated nullable uniqueness slots to prevent multiple leader ranks or leader members in one gang.
- Keep only `oxmysql`, `ox_lib`, `cm-playerdata` and `cm-ui` as hard dependencies. Inventory/items/weapons/vehicles/catalog/chat/admin remain guarded owner integrations to avoid hard cycles.
- Do not auto-execute the resource-local migration in this cycle. Startup validates and fails closed with an explicit migration instruction rather than silently mutating an unapproved database.

## Cycle 5 baseline decisions

- Use `C:\Users\xumit\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe` for repository Python checks in this environment. This is an execution-environment choice only and adds no repository dependency.
- Treat the validator's three warnings and the scanner summary's existing unresolved relationships as baseline debt, not gang regressions. Compare later scans against this baseline.
- Keep F8 and `/gang` for the gang dashboard and `/g` for gang chat because source searches found no current registrations. Do not modify the existing organization or interaction key mappings.
- Graphify is supplemental only. The CM scanner and direct source inspection remain authoritative for FiveM events, exports, NUI callbacks and database contracts.
