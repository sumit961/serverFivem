# CM Population

`cm-population` removes GTA's ambient population while leaving NPCs created by
CM gameplay resources available.

It disables:

- ambient pedestrians and scenario pedestrians;
- NPC road traffic and parked vehicles;
- random police, emergency, gang, boat, and military dispatch;
- random garbage trucks, boats, trains, and low-priority vehicle generators.

It intentionally preserves scripted characters such as store clerks, gun-store
clerks, clothing staff, parking attendants, vehicle dealers, and character
preview peds. Those are created directly by their owning resources and are not
part of GTA's ambient population system.

## Configuration

Edit `config.lua` and restart the resource after changing a setting:

```text
restart cm-population
```

All density values default to `0.0`. A value of `1.0` restores GTA's normal
density for that category. Persistent suppression settings can be enabled or
disabled individually in the same file.

The resource is started by `ensure cm-population` in the main `server.cfg`.
