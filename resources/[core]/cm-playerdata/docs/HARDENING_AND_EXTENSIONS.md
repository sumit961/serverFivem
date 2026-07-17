# cm-playerdata — Hardening & Extension Guide

cm-playerdata is the **spine**: it owns loaded character state, the visible
character ID, cash/bank, vitals, death state, identity memory, and the
interaction-menu registration API. Everything else on the roadmap is built as a
**separate resource** that calls playerdata's exports. That is what keeps this
resource stable — you should rarely need to edit it again.

## What the hardening layer added (server/hardening.lua)

This file is additive and never edits main.lua. It adds:

### Player-to-player money transfer
```lua
-- Move money between TWO DIFFERENT players, atomic with audited refund on failure.
local ok = exports['cm-playerdata']:TransferMoneyBetween(fromSrc, toSrc, 'cash', amount, 'give_cash')

-- Verbose variant returns an error code you can show the user:
local ok, err = exports['cm-playerdata']:TransferMoneyBetweenDetailed(fromSrc, toSrc, 'cash', amount, 'give_cash')
-- err ∈ insufficient_funds | same_player | player_not_loaded | invalid_amount | ...
```
The built-in `TransferMoney` only moves between one player's own cash/bank; this
is the one to use for "give cash", trades, and player-funded purchases.

### Persistent identity memory
```lua
-- Remember a name in-memory AND in the DB (survives restarts):
exports['cm-playerdata']:KnowPlayerIdentityPersistent(viewerSrc, targetSrc, 'handshake')

-- Warm-load what a character already knows (e.g. on join):
local rows = exports['cm-playerdata']:GetKnownIdentities(ownerCharId)
```
Backed by the `cm_known_identities` table (auto-created). Solves the metadata
JSON bloat and makes recognition queryable.

### Roadmap helpers
```lua
exports['cm-playerdata']:ArePlayersWithin(aSrc, bSrc, 3.0)  -- server-side distance gate
exports['cm-playerdata']:GetAffiliation(src)               -- { familyId, family, organizationId, organization }
```

## Building the roadmap features (no playerdata edits)

Every one of these is a **new resource** that (1) registers a G-menu option via
`RegisterInteractionOption`, and (2) handles the server event through the
existing `extensionInteraction` pipeline, which already verifies source,
validates the target, checks server-side distance, rate-limits, and checks death
state before firing your handler.

| Feature | New resource | Key playerdata exports it uses |
|---|---|---|
| Give cash | cm-interactions (or reuse) | `TransferMoneyBetween` |
| Heal / medkit treat | **cm-medical** | `Heal`, `RevivePartial`, `IsDead`; checks `cm-inventory` for the medkit item |
| Give car key | **cm-vehiclekeys** | `GetCharacterId`, `ArePlayersWithin` |
| Sell vehicle/house/business | those resources | `TransferMoneyBetween`, `GetCharacterId` |
| Family invite / rank / kick | **cm-families** | `SetFamily`, `GetAffiliation` |
| Organization invite / rank / kick | **cm-orgs** | `SetOrganization`, `GetAffiliation` |
| Trade | **cm-trade** | `TransferMoneyBetween` + `cm-inventory` |
| Get in trunk / carry / escort | **cm-medical** / **cm-police** | `IsDead`, `ArePlayersWithin` |
| Arrest | **cm-police** | permission-gated option; `GetCharacterId` |
| Frisk / view inventory | **cm-police** + **cm-inventory** | `ValidateInteractionTarget`; inventory owns the list |
| Emotes / animation interactions | **cm-emotes** | register options; client plays anims |

### Minimal extension pattern (server side of any new resource)
```lua
-- 1) Register the menu option (client) via RegisterInteractionOption, pointing
--    its action id at an event your resource owns.
-- 2) Handle it here. The extensionInteraction pipeline already validated
--    source/target/distance/rate-limit/death before calling you.
AddEventHandler('cm-medical:server:treat', function(src, target, actionId, payload, ctx)
    -- ctx = { source, target, sourceCharacterId, targetCharacterId, distance }
    if not exports['cm-inventory']:HasItem(src, 'medkit') then
        TriggerClientEvent('cm-playerdata:client:notify', src, 'You have no medkit.', 'error')
        return
    end
    exports['cm-inventory']:RemoveItem(src, 'medkit', 1)
    exports['cm-playerdata']:RevivePartial(target, 50, 'medkit_treat')
end)
```

Because permission, distance, rate-limit, and death checks live in the shared
pipeline, each new feature is small and consistent — and playerdata itself stays
untouched.

## One recommended edit to main.lua (optional, your call)

The existing `cm-playerdata:server:giveCashToPlayer` handler is well-secured
(validates distance/interaction, caps the amount) but does `RemoveMoney` then
`AddMoney` with **no refund if the credit leg fails** — if the target drops in
that window, the cash disappears. Replacing those two calls with the atomic
helper closes it:

```lua
-- inside giveCashToPlayer, replace the RemoveMoney/AddMoney pair with:
local moved, err = exports['cm-playerdata']:TransferMoneyBetweenDetailed(src, target, 'cash', amount, 'player_give_cash')
if not moved then
    NotifyPlayer(src, err == 'insufficient_funds' and 'You do not have enough cash.' or 'Cash transfer failed.', 'error')
    return
end
```

This is the only change I'd suggest making *inside* main.lua. Everything else is
additive.

## Note on the medkit item
There is currently no `medkit` item in the server. Add it through `cm-items`
(the unified registry) so it exists server-wide, then the cm-medical flow above
works. That's an items-registry change, not a playerdata change.
