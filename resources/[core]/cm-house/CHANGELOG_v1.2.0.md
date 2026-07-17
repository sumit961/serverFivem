# cm-house v1.2.0 — Real garage vehicles

- Replaced transparent local garage ghosts with real OneSync network vehicles.
- Parked cars are fully visible, collidable, unlocked, F-enterable, and targetable by the cm-vehicles G menu.
- Parked cars begin frozen/engine-off; Left Ctrl starts the engine and releases the bay freeze.
- Added interior vehicle-exit marker. Drive a parked car to it and press E to move the same entity into world bucket 0.
- Calling a car from the slot menu moves the existing garage entity outside instead of creating a duplicate.
- Garage entities unload when the final player leaves the garage and reload from the database on entry.
- Fixed outside parking plate lookup to use the CM state-bag plate while the visible GTA plate is blank.
