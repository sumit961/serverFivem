# RUNTIME TESTS

## GANG-004 invite expiry race repair regression

- Decline an invitation at the expiry boundary while the periodic expiry
  worker resolves pending invitations. Verify exactly one terminal status and
  that a losing zero-row decline produces neither a success notification nor
  an `invite_declined` activity row.
- Accept an invitation at the expiry boundary while the periodic expiry worker
  resolves pending invitations. Verify exactly one outcome: either the invite
  is accepted and one membership exists, or it is expired and no membership
  exists. A zero-row conditional invite consume must roll back membership.
- Submit simultaneous Accept/Decline and duplicate Accept responses for the
  same invite. Verify one terminal invite status, at most one membership row,
  and no success notification/activity entry for a losing response.

## GANG-008 armory lock repair regression

- During an armory checkout, force a handled inventory-delivery failure and a
  server-side exception after the checkout lock is acquired. Verify a retry is
  not permanently `request_busy` and no duplicate item or issued journal row
  results.
- Disconnect the requesting character while checkout is in progress, reconnect,
  and retry the same gang/item. Verify all character-owned armory locks and
  cooldown state were cleared without requiring a `cm-gang` restart.

## GANG-011 final release gate

- Run every GANG-002 through GANG-010 suite below on a disposable database and
  non-production FXServer with at least two clients and multiple routing
  buckets. Record actual pass/fail evidence before deployment.
- Restart `cm-gang` and each soft owner independently, exercise direct forged
  event/callback/NUI requests, and inspect server logs for errors, stale locks,
  orphan entities/keys/invites or sensitive account/session data.
- Confirm the migration rerun preserves customized rows and that all twenty-two
  core acceptance conditions remain true under multiplayer concurrency. Static
  completion is review-ready only; it is not runtime certification.
- Submit two return callbacks for the same gang fleet vehicle simultaneously.
  Verify one succeeds, the other is busy/rate-limited, only one location and
  activity transition is recorded, and a forced owner error releases the lock.

## GANG-010 central administration and recovery

- Open F11 as ranks with neither, view-only, and manage gang permissions.
  Verify the Gangs tab is hidden/readonly/interactive respectively, contains
  exactly four fixed rows, and has no create/delete/recruitment control.
- Edit all four identities, enabled state, color and valid/invalid local asset
  keys. Restart both resources and verify database values persist and arbitrary
  URL/path/script values are rejected.
- Assign a leader by valid CID, replace that leader, remove the leader, and try
  an unknown CID or a character already in another gang. Verify one leader at
  most, correct demotion, one-gang-only, immediate state refresh and no family,
  Police, EMS or legal membership change.
- Edit every non-leader rank name/tier/permission and test duplicate name/tier,
  unknown permissions and attempts to weaken the leader rank. Verify failures
  leave database/cache unchanged and successful edits survive restart.
- Set/reset headquarters, armory, stash and fleet while changing routing
  bucket. Verify server entity coordinates/heading/bucket were stored, supplied
  browser coordinates are ignored, and invalid NPC models fail closed.
- Configure valid/invalid weapon/ammo IDs and fleet models, exercise placement
  cancel/confirm/disconnect, then verify limits, stable `vehicle_id`, no duplicate
  fleet entity and no firearms-license check.
- Trigger each `gangAdminAction` directly while out of admin mode, without the
  permission, with malformed IDs/data and at high rate. Verify every request is
  denied or throttled and no partial mutation/activity row is produced.
- Run stale-invite expiry and cache reload recovery; verify only expired invites
  change, active invites survive, locks do not stick, and safe activity/admin
  logs contain character IDs but no account identifiers or server IDs.
- With view-only permission, confirm configured armory/fleet rows and recovery
  counts are visible but every mutation remains disabled and fails if invoked
  directly. After identity/leader/rank changes, verify dashboard permissions and
  every online member's privacy-safe `cmGang` state update without a restart.

## GANG-009 persistent fleet

- Through the GANG-010 admin UI, configure a public `rn-vehicleshop` model for
  each fixed gang, begin placement, move the dummy, confirm, and verify the
  saved server coordinates/bucket and stable `vehicle_id`. Cancel, timeout,
  disconnect and restart during placement and verify no dummy or lock remains.
- Call as authorized, unauthorized, under-tier, disabled, distant and
  wrong-bucket members, including direct callback calls. Only an authorized
  member at the enabled fleet facility may call the configured vehicle.
- Call concurrently from two clients and call an already live/occupied vehicle.
  Verify one physical entity per `vehicle_id`, no second database record, no
  occupied recall, and correct available/deployed/occupied dashboard status.
- Drive the exact vehicle back to its fixed space and return it. Attempt with a
  different entity/model/network ID, as passenger, remotely and cross-bucket;
  verify all invalid requests fail and the original `vehicle_id` remains.
- Damage engine/body/tank to ordinary and genuine zero values, change fuel and
  mods, then return/call/restart. Verify condition is preserved exactly and no
  gang path silently repairs, refuels or replaces zero health.
- Verify drive/lock/engine/store/trunk access follows current membership,
  `gang.vehicle`, minimum tier and enabled state. Remove permission/membership,
  demote, disable and disconnect; access must revoke without personal ownership
  or a permanently lent key. Confirm the session-key record clears on return,
  character switch, disconnect and resource stop. Sell/delete/key-manage/
  family-share must stay denied.
- Restart `cm-gang`, `cm-vehicles`, and `rn-vehicleshop` in safe start orders;
  verify missing soft owners fail closed, then recover without duplicate entities.

## GANG-008 stash and armory

- Apply `sql/002_cm_gang_armory_issues.sql` to a disposable database, restart
  `cm-gang`, and verify schema readiness. Reapply it and verify idempotency.
- Open each fixed gang stash as an authorized nearby same-bucket member and
  verify four isolated `gang_stash/<gang_id>` owners. Test deposit, withdraw,
  swaps, stacks, metadata, equipped items, full inventory and locked bag slots.
- While the stash is open, remove `gang.stash`, remove membership, disable the
  gang/facility, walk away and change routing bucket. Every later move must fail
  closed. Restart/disconnect must clear the open context.
- Verify successful deposit/withdraw activity contains actor CID, item ID and
  quantity only, with no full metadata/inventory contents or server ID.
- Configure enabled weapon and ammunition catalog IDs with varying minimum
  tiers, quantities and limits. Verify only current enabled `cm-weapons` rows
  display and direct callback calls cannot select an arbitrary item/quantity.
- Checkout as authorized/unauthorized/distant/wrong-bucket/disabled members.
  Verify cooldown, full-inventory failure, limit enforcement, simultaneous
  requests, server-generated weapon serial/durability/hash metadata and no
  firearms-license or duty check.
- Force inventory delivery failure and verify the journal becomes `void` and no
  item is created. Verify successful issues have one journal/activity row and
  weapon/ammunition behavior remains correct after reconnect/restart.

## GANG-007 chat, dashboard, NPC and facilities

- Open `/gang` and F8 as a member and non-member. Verify non-members receive no
  data/NUI, Escape closes cleanly, refresh preserves the selected gang, and
  F6/F9/TAB/J/G behavior is unchanged.
- Exercise every dashboard section with and without its permission. Verify
  activity is absent without `gang.view_logs`, member data is absent without
  `gang.view_members`, and no dashboard/NPC recruitment path exists.
- Assign a lower member's rank and remove a lower member through the dashboard.
  Attempt self, leader, equal/higher, stale rank and direct NUI callback calls;
  verify owner hierarchy checks fail closed and activity/state refreshes.
- Send through both `/g` and the GANG chat tab as authorized, unauthorized,
  disabled and non-member characters. Verify only current same-gang players
  receive it, character identity/rank/tag formatting is correct, cooldowns
  apply, and cross-gang/manual group spoofing fails.
- Configure one allowlisted headquarters NPC for each gang. Verify only the
  current member's NPC appears, wrong-bucket/disabled/missing-coordinate/
  non-allowlisted-model rows spawn nothing, E opens the dashboard, prompts hide
  while NUI is open, and ped/prompt/focus cleanup works on restart/disconnect.
- Verify missing logo/art uses the text crest fallback and custom gang accents
  remain readable without external URLs or `backdrop-filter`.

## GANG-006 search and atomic item robbery

- Test `gang.search` and `gang.rob_items` independently against cuffed, dead,
  standing, distant and cross-bucket players, including direct event calls.
- Verify search exposes only sanitized data. Test expired, reused and stale
  tokens after reopening the view or changing the victim row.
- Verify `id_card`, `driver_license` and a configured protected test item cannot
  move, while ordinary items remain transferable.
- Transfer partial/full stacks, unique items, clothing, ammo and a serialized
  weapon; verify exact quantity, durability, serial and metadata preservation.
- Fill destination slots/weight and verify the victim loses nothing. Attempt
  equipped-bag theft with occupied/overweight backpack state and expect denial.
- Test equipped weapon/ammo/bodyarmor refresh for both players without minted
  or duplicated weapon state.
- Submit the same row simultaneously from two robbers and race victim move/drop/
  give operations on disposable MySQL; verify quantity and metadata conservation.
- Disconnect either player and restart both resources mid-flow; verify tokens
  and locks clear and audit rows contain safe summaries, not full inventories.

## GANG-005 robbery authority and cash

- As ranks with and without `gang.rob_cash`, target a cuffed, dead and normal
  standing player. Verify Rob Cash appears only for authorized cuffed/dead
  targets and every direct event invocation against a standing target fails.
- Attempt self, offline/stale, over-three-metre and different-routing-bucket
  requests, then change permission/disable the gang after opening the amount
  prompt. Verify the final server validation denies every stale request.
- Rob valid amounts including the full wallet balance. Verify victim cash
  decreases by exactly the amount, robber cash increases exactly, and both bank
  balances remain unchanged. Test zero, negative, decimal, overflow and more
  than victim cash; verify no balance changes.
- Have two gang members rob the same target simultaneously and spam one actor's
  event. Verify the target lock/cooldown admits at most one mutation, no money is
  created/lost, and locks clear after failure, disconnect and resource restart.
- Disconnect robber and victim at each stage and force a stale DB/cache balance
  during a disposable-server test. Verify the conditional owner update either
  moves both sides once or neither side, then inspect economy transactions and
  `cash_stolen` activity for safe CIDs/amount only.

## GANG-004 G-menu invitations

- As a member with `gang.invite`, look at a nearby gangless player and press G;
  verify Gang > Invite to Gang appears. Verify it is absent for civilians,
  ranks without permission, disabled gangs, existing gang members, self/stale
  targets and after switching targets rapidly.
- Send an invite and verify the target receives the correct local character
  name and gang display name with Accept/Decline. Accept within 60 seconds and
  verify the server-selected lowest non-leader rank, one membership row,
  accepted invite status and immediate privacy-safe `cmGang` state.
- Decline and let separate invites expire; verify no membership is created,
  statuses resolve, the prompt does not grant later access, and safe activity
  rows exist without server/account identifiers.
- Attempt direct `gang_invite`/respond event calls, self invite, duplicate
  invite, rapid invite, occupied target, modified invite ID, reused response,
  and concurrent Accept requests. Verify all fail closed without duplicate
  membership or a fifth/different gang/rank assignment.
- Move beyond three metres or into another routing bucket before sending and
  before accepting. Verify both stages reject. Disconnect inviter/target during
  the prompt and restart `cm-gang`; verify pending invitations, response locks,
  cooldowns and G-menu options do not remain usable/stuck.
- Keep a test character simultaneously in family and a legal organization,
  accept a gang invitation, and verify those memberships remain unchanged and
  no duty check is introduced.

## GANG-002 schema/startup

- On a disposable database, apply `resources/[core]/cm-gang/sql/001_cm_gang.sql` twice. Verify exactly four `cm_gangs` rows, 20 initial rank rows, 16 facility rows, and one migration journal row.
- Rename/re-tier/edit permissions on an existing rank and customize each gang identity, rerun the migration, and verify none of those values are overwritten and no additional default ranks appear.
- Attempt to insert `gang_5`, a second membership for one character, a member referencing another gang's rank, a second leader rank and a second leader member; verify each fails.
- Start/restart `cm-gang` after migration and verify the database-ready message. Test an unmigrated disposable database and verify the resource fails closed without creating tables or accepting gameplay mutations.
- Verify `gang_1` through `gang_4` remain disabled and leaderless until explicit admin configuration in the later owner/admin plan items.

## GANG-003 owner domain, ranks and members

- With one enabled test gang and an explicitly assigned leader, restart
  `cm-gang`; verify the leader/member/rank cache loads and each online member's
  `cmGang` state contains only gang identity and rank presentation (no CID or
  permission map).
- Verify `GetGangForCharacter`, `HasPermission`, and
  `GetPermissionDecision` for a leader, lower rank, disabled gang, unknown
  permission, non-member, and after resource restart.
- As authorized and unauthorized ranks, create/rename/delete ranks and change
  permissions. Verify unknown permissions, duplicate tiers/names, leader-rank
  edits, ranks at/above the actor, grants the actor lacks, an in-use rank, and
  rapid duplicate mutations all fail closed.
- Promote, demote, and remove an existing lower member. Verify self, leader,
  equal/higher target, destination at/above the actor, cross-gang target, and
  stale rank IDs fail without database or cache changes.
- Transfer leadership to an existing member. Verify the prior leader receives
  the highest non-leader rank, the target receives the one leader rank/flag,
  `cm_gangs.leader_character_id` changes in the same transaction, both state
  bags refresh, and lower/non-members cannot transfer.
- Disconnect during/after a mutation and restart the resource; verify no gang
  lock or cooldown remains permanently and database authority reloads cleanly.
- Confirm rank/member/permission/leader activity rows contain gang ID, action,
  actor CID, optional target CID, and safe details without server/account IDs.
