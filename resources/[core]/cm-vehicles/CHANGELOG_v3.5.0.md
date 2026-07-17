# cm-vehicles v3.5.0

- Added cm-family + cm-vehiclekeys access chain for shared family vehicles.
- Grants a revocable family session key before a non-owner vehicle leaves the family garage.
- Engine, lock, vehicle info and trunk actions use action-specific key validation.
- Returning a vehicle to the family garage revokes all family session keys for that vehicle.
- Vehicle information displays Family Garage Access with family tag/name.
- Vehicle information uses the same catalog image as rn-vehicleshop.
- Legal ownership is never transferred when a car is shared.
