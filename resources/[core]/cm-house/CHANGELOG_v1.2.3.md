# cm-house v1.2.3

- Removed the failing cross-resource network-id resolution step.
- cm-vehicles now owns creation, configuration, condition reading, driver validation, promotion and deletion of garage entities.
- cm-house no longer deletes a valid car merely because its own resource could not immediately resolve the network ID.
- Prevents temporary local ghosts, `local display vehicle` errors and cars disappearing after spawn.
- Adds database rollback if a retrieved vehicle cannot be promoted outside.
