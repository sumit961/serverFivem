# cm-admin family activity integration

The cm-admin UI should own staff-facing history. cm-family exposes read-only server exports:

```lua
local ok, rows = exports['cm-family']:AdminGetHighRiskFamilyActivity(adminSource, {
    familyId = optionalFamilyId,
    limit = 100,
})

local ok, rows = exports['cm-family']:AdminGetFamilyActivity(adminSource, familyId, {
    limit = 100,
    category = 'bank',
})
```

cm-family calls `cm-admin:HasPermission` and accepts one of:

- `family.logs.view`
- `admin.logs.view`
- `family.view`

High-risk rows are also emitted as a server-only event:

```lua
AddEventHandler('cm-admin:server:familyActivity', function(row)
    -- Add to the cm-admin Logs module / live alert list.
end)
```

Do not expose these exports through a public client event.
