# Future PlayerData Extensions

These features should be added through dedicated resources using `cm-playerdata` exports/events, not by putting all gameplay into playerdata.

## Downed State Variety
Recommended flow:
- `injured`: player can crawl / speak quietly.
- `critical` or `comatose`: blacked out / no normal movement.
- `dead`: respawn/deathscreen state.

`cm-playerdata` should own the replicated state and death location. EMS/medical gameplay should own treatment, carry, stretcher, and recovery rules.

## Carry / Escort / Dragging
Use the extensible G-menu registration API:
- Register a `medical.drag` or `police.escort` option.
- Server validates distance, death state, permissions/job, and cooldown.
- Client action can attach/detach entities using safe native wrappers.

## Frisk / Inventory Inspection
Use G-menu options registered by police/crime resources:
- Server checks permission/job/context.
- `cm-inventory` owns the item list and inspection UI.
- `cm-playerdata` only validates target identity/distance/death state.

## Persistent Recognition Matrix
Future table suggestion:
```sql
CREATE TABLE IF NOT EXISTS cm_known_identities (
  owner_character_id BIGINT NOT NULL,
  known_character_id BIGINT NOT NULL,
  reason VARCHAR(32) NOT NULL DEFAULT 'met',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (owner_character_id, known_character_id)
);
```

This lets players remember names permanently after handshake/shared ID even across restarts.
