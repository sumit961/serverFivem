# cm-law v3.3.0 — Persistent Law Fleet

- Law and Police fleet entries continue to reference the existing Manage Vehicle catalog and one persistent `vehicle_id`.
- Enabled, configured vehicles reconcile after `cm-law` or `cm-vehicles` starts and on a low-frequency recovery check.
- Fleet location changes now save the actual linked persistent vehicle's server-observed position; fleet location dummies are no longer used by these flows.
- Normal officers no longer receive a Fleet NPC spawn action. Leaders/managers can set rank and location, recall one unoccupied vehicle, or recall their own organization's fleet.
- Admin fleet tools support individual/all recall and open the existing Manage Vehicle editor for tuning. Saved appearance changes update `cm-vehicles` mods for configured persistent vehicle IDs.
- Vehicle recalls refuse occupied vehicles, preserve organization boundaries, and retain the existing persistent vehicle record.
- Vehicle G-menu files and Law G-menu/operations behavior are unchanged.

No database migration is required: both Law fleet tables already contain the persistent `vehicle_id`, location, rank, and enabled fields.

Manual FiveM validation remains required for startup reconciliation, entity access, recall safety, and UI behavior.
