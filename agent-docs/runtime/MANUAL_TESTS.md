# Manual FiveM tests

Server-console validation does not capture the FiveM client F8 console or prove ped, NUI, multi-player, vehicle, OneSync streaming, NPC, map/blip, wardrobe, or animation behaviour. Add exact scenario-specific steps here when one of those gates is reached.

## cm-doctor medicine route repair

1. Join the development server with a test character below maximum health.
2. Use one configured medicine item, such as `bandage`, from `cm-inventory`.
3. Confirm one item is consumed, health increases by the configured amount, and the cooldown/message is correct.
4. Confirm an unconscious character cannot use medicine to revive and that a second immediate use is rejected by cooldown.
5. Check the client F8 console and server console for new errors.
