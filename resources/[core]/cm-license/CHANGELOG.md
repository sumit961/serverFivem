# cm-license 1.2.1

## Picking a discarded license back up restores it

Dropping the physical card revoked the license, but picking it back up did
nothing — you were left holding a card with no entitlement behind it. Both
halves of that contract now exist: picking up **your own** discarded card
re-activates the same license row, keeping its original expiry rather than
issuing a fresh one.

The restore is deliberately narrow. It only fires when every one of these
holds, and the checks live in the SQL `WHERE` clause so a race cannot slip
past them:

- The character picking it up is the character the card was issued to
  (checked against both cm-playerdata and the item metadata).
- The revocation was caused by discarding it. An **admin revocation is never
  undone this way** — if `/revokelicense` ran while the card lay on the
  ground, picking it up leaves it revoked.
- The original expiry is still in the future. A license that expired while it
  was out of your hands stays dead.
- The card matches the issuance still on record. If you retook the test and
  were issued a new license, the old card on the ground is superseded and
  cannot restore anything.

Anyone else who picks the card up gets told it belongs to someone else and
gains nothing — the card is just a prop for them, which leaves stolen-ID
roleplay intact.

Where the restore does not apply, the player is told why rather than left
guessing: revoked by the authorities, expired, superseded, or not yours.
`already_active` is silent, since nothing was wrong.

### Wiring note

This listens for `cm-inventory:server:itemPickedUp`, named to mirror the
`cm-inventory:server:itemDropped` event the drop half already uses. **Confirm
that is what your cm-inventory actually fires** — I could not check it from
here. If the name differs, either change the one `AddEventHandler` line in
`server/main.lua`, or call the exported hook from cm-inventory instead:

```lua
exports['cm-license']:OnLicenseItemPickedUp(src, ownerId, itemName, amount, metadata)
```

The handler assumes the same argument order as the drop event. It is
idempotent, so a double call is harmless.

---

# cm-license 1.2.0

Builds on the 1.1.0 bug-fix pass. This release adds the three features you
picked, rebuilds the NUI, and fixes the missing cursor on the result screen.

## Added

### Multiple routes per license type, drawn at random
`unique_route_per_type` is dropped, so a type may own as many routes as you
record. Each exam draws one enabled route at random (`Cache.GetRandomRoute`),
so players cannot memorise a single circuit. Routes with fewer than two points
are skipped automatically.

- `cm_license_routes` gains `label` and `enabled`; `cm_license_active_tests`
  gains `route_id`, so you can see which route an attempt used.
- The route builder now **adds** a route instead of replacing the only one.
  Pass a `routeId` to re-record an existing one in place.
- New admin screen: **Manage Routes** per test — enable/disable, re-record and
  delete individual routes, with a live count of what is in rotation.
- The index drop and the new columns are applied automatically at resource
  start (`sql/005` is there for manual installs).

### Admin commands
- `/givelicense <id> <type> [days]` — issues and delivers immediately.
- `/revokelicense <id> <type> [reason]` — revokes and removes the card.
- `/licenses [id]` — lists a character's licenses with status and expiry.

Each respects its own permission (`issue_licenses`, `revoke_licenses`,
`manage_licenses`) and writes a cm-admin audit entry.

### Server-enforced timer with HUD countdown
The clock starts when the fee is taken and is enforced server-side from
`TestSession.TimeoutMinutes`, checked every 10s independently of the slower
maintenance pass. The HUD shows a live countdown that turns red in the last
minute, alongside checkpoint progress and (on ground exams) mistakes. Time
remaining is re-synced from the server on every checkpoint, so a laggy client
cannot drift. The confirmation dialog now reads its "Time Limit" from the same
config value rather than the hardcoded 20 minutes it used to display.

## Fixed

**No mouse on the result screen.** The pass/fail dialog was shown without NUI
focus, so its Close button could not be clicked. It now takes focus with
`SetNuiFocusKeepInput(true)` — you get a cursor while still controlling your
character, which matters because the same screen can appear mid-drive after a
failure. Closing hands focus back; if the player never clicks, focus is
released automatically (10s in the UI, 15s hard release on the client).

## UI rebuild

- **Cinematic hero art** on the confirmation and result screens, with a
  distinct placeholder scene per class: a car on a night highway, a boat on
  open water, a helicopter over ridgelines. Each is generated SVG — no image
  files ship — with a colour grade, scanlines, vignette and a slow drift so it
  reads as a shot rather than an icon.
- **Dropping in real art is one line.** Set the CSS variable on the hero:
  `#testHero { --art-image: url('art/driver.jpg'); }`. The photo layer sits
  above the SVG and inherits the same grade, scanlines and vignette.
- Confirmation screen now shows fee, time limit, examination vehicle, validity
  and (where relevant) mistakes allowed, instead of three static rows.
- "My Licenses" is a card list with per-class icons, status pills and a
  validity meter that turns amber under five days and red on expiry.
- Result screen gained a PASS/FAIL stamp over the artwork.
- Admin screens rebuilt: cards with route/checkpoint/fee summaries and inline
  actions. Destructive actions arm on first click and confirm on the second,
  because `window.confirm` is unreliable inside CEF.

## Migration notes

Nothing to run by hand — `Database.Init` applies the new columns and drops the
retired index at start-up. `sql/005_cm_license_multi_route.sql` is provided for
manual installs and is safe to run repeatedly. Existing single-route setups
keep working unchanged; they simply have a rotation of one until you record
more.
