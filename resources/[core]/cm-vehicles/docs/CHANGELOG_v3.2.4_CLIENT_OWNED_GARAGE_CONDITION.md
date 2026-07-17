# cm-vehicles v3.2.4

- House-garage vehicles now use the tokenised client-owned network creation path by default.
- Applies condition, fuel, mods and performance before the network entity is accepted.
- Fixes server-setter vehicles whose engine/body health nodes remained at 0.
- Normalises legacy persisted 0..1 health values to GTA's 0..1000 scale.
- Adds stricter vehicle readiness checks before finalisation.
