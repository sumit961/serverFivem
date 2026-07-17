# cm-house v1.3.2.9 — Persistent Garage Slots

## Corrected garage behaviour

- House parking spaces now remain assigned while their vehicle is outside.
- Driving a vehicle out no longer clears `cm_house_vehicle_slots.vehicle_id`.
- **Recall car** always returns the assigned vehicle into the same garage space.
- House garage menus no longer call, spawn, or recall vehicles outside.
- **Remove car** explicitly clears the slot assignment so another vehicle can be added.

## Slot state model

- `cm_house_vehicle_slots.vehicle_id` means the vehicle owns/reserves the space.
- `is_stored = 1` and `garage = house:<id>` means it is physically inside.
- `is_stored = 0` with an assigned slot means it is currently outside in the city.

## Recall safety

- Recall validates the property, slot, assigned vehicle ID, access, and routing bucket.
- Recall refuses vehicles stored in public garages, impounds, or other storage systems.
- Recall refuses while any player occupies the vehicle.
- Occupancy is checked again after the database yield to close the enter-during-recall race.
- Live health, fuel, dirt, windows, doors, and tyres are persisted before returning the entity.
- Existing world entities are moved into the private garage bucket; missing entities are recreated.
- Failed recalls restore the outside database state while preserving the slot reservation.

## Assignment and removal

- A vehicle already assigned to any house space cannot be assigned elsewhere until removed.
- Occupied spaces cannot be silently replaced; remove the current assignment first.
- Removing an outside vehicle's assignment leaves its city entity untouched.
- Removing a physically stored vehicle deletes only the garage display and frees the assignment.

## Return-zone and restart fixes

- Returning a vehicle uses its reserved space first.
- A vehicle assigned to another house must be removed there before parking here.
- Startup reconciliation preserves valid `is_stored = 0` slot reservations.
- Migration `008_reseat_garages.sql` was updated so rerunning it no longer clears outside reservations.

No new SQL migration is required.
