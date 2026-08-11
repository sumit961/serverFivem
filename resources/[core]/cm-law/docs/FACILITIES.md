# CM Legal Organization Facilities

`cm-law` owns reusable facilities for `sahp`, `sheriff`, `fib`, and `army`.

Facility types: `front_desk`, `wardrobe`, `armory`, `storage`, and `fleet`.

Server export used by `cm-admin`:

```lua
local ok, message = exports['cm-law']:AdminSetFacility(
    adminSource,
    organizationId,
    facilityType,
    reset -- boolean
)
```

The export validates `orgs.manage` through `cm-admin`. Organization leaders
use the namespaced `cm-law:server:setFacility` callback, which independently
validates their membership and management authority.

Armory and storage containers are owned by `cm-inventory` under
`legal_org_armory/<organizationId>` and
`legal_org_storage/<organizationId>`. Access is revoked when membership,
duty, proximity, or routing-bucket context becomes invalid.

The fleet facility intentionally fails closed until persistent vehicles are
assigned through the vehicle owner/catalog integration. It must never spawn a
client-selected model directly.
