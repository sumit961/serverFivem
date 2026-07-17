# Racing Harness Integration — v3.3.9

Racing-harness installation is server-authorized only. The old public client/server events and `/installharness` test command have been removed.

## Required flow

Your trusted resource must:

1. Validate the purchase or item use on the server.
2. Consume the `racing_harness` item or charge the player.
3. Resolve the target vehicle plate and network ID.
4. Call the cm-vehicles server export.
5. Refund/restore the item if the export returns `false`.

```lua
local ok, reason = exports['cm-vehicles']:InstallRacingHarness(source, plate, netId)
if not ok then
    -- Restore the consumed item/payment here.
    print(('Harness install failed: %s'):format(tostring(reason)))
end
```

## Authorized resources

Only resources listed in `CMVehicles.Config.Security.authorizedHarnessResources` may call the export. The supplied defaults are:

```lua
authorizedHarnessResources = {
    ['cm-tuning'] = true,
    ['cm-itemactions'] = true,
    ['cm-admin'] = true,
}
```

Add another resource explicitly before allowing it to install a harness. Never recreate a public net event that calls this export without item/payment validation.

## Export

```lua
InstallRacingHarness(src, plate, netId) -> boolean, string|nil
```

The export validates:

- calling resource authorization;
- online player/character;
- vehicle database identity;
- network entity identity;
- routing bucket and proximity;
- player access to the vehicle;
- whether a harness is already installed.

The installed state is saved in vehicle metadata and replicated as `cmRacingHarness`.
