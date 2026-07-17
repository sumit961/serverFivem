# cm-admin integration — cm-house v1.7.0

The intended production workflow is:

1. Enter admin mode in `cm-admin`.
2. Open the House module.
3. Create reusable interior and garage templates from the module.
4. Create a property and select those existing templates.

Recommended module buttons:

```lua
exports['cm-house']:OpenAdminPanel(source, 'interiors')
exports['cm-house']:OpenAdminPanel(source, 'garages')
exports['cm-house']:OpenAdminPanel(source, 'houses')
exports['cm-house']:OpenHouseCreator(source)
```

Recommended permission keys:

- `house.admin.open`
- `house.create`
- `house.admin.properties`
- `house.admin.interiors`
- `house.admin.garages`
- `house.admin.photos`
- `house.admin.recovery`

A garage template is captured as:

1. Player entry.
2. One or more vehicle/on-foot exits.
3. Physical parking spaces using the cyan placement car.

The saved capacity equals the number of placement cars positioned. There is no garage settings/customization point.
