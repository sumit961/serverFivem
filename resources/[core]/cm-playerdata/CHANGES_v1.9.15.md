# CM PlayerData v1.9.15

- Native GTA health recharge is continuously disabled.
- Unexpected client-side health increases are clamped back to the last authoritative health.
- Legitimate healing remains available through cm-playerdata server exports/events.
- Inventory is closed before the death screen takes focus.
- cm-inventory weapon/ammo death drop is triggered at `SetDead(true)` (unconscious), not at finished-off death.
- Death-drop state resets on revive/respawn so future deaths work correctly.
