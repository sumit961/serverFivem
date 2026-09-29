# cm-house v1.8.16

## Security hardening (priority audit follow-up)

- `ListWeaponStorageRecovery` and `RestoreWeaponStorageRecovery` exports now require the same cross-resource integration authorization every other writable export in this resource already enforces. Previously any co-located resource could call them directly.
- `RestoreWeaponStorageRecovery` now writes a house activity-log entry (recovery id, restored item, target character, authorizing resource) for staff-only audit visibility.
- `TransferFamilyHouseOwnership` now requires the `family` integration scope, matching its sibling exports in `sv_phase2.lua`. The transfer's activity-log entry is now attributed to the actor cm-family identified (the outgoing founder), not fabricated from the new owner.
- `getTemplates` now requires the same admin scope as every other template-management callback in `sv_templates.lua`.

## Weapon storage integrity

- Fixed weapon durability being silently forced to 100% on deposit even when `requireFullWeaponDurability` is disabled. A damaged weapon's genuine condition is now preserved instead of being repaired for free.
- Withdrawal cooldown is now scoped per character+house instead of per individual storage point, so a family house with multiple armories can no longer have its cooldown bypassed by switching points. Personal houses now enforce the same cooldown; previously they had none.

## Property access validation

- `openStash` now validates server-side physical proximity to the specific stash, not just general house access.
- Removed the dead, unvalidated `cm-house:server:openWardrobe` server event handler. The live wardrobe flow is entirely client-local and never called it.
- `buyHouse` and `sellHouse` now require the player to be physically near the property door before the transaction proceeds. Purchase/sale money and database-reservation logic is unchanged.

No UI redesign was performed. No database migrations were required.
