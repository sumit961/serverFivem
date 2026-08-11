# cm-vehicles v3.5.4

- `SpawnVehicleFromParking` can now accept a trusted `allowAuthorizedAccess` option.
- Non-owner retrieval still calls the authoritative `CanUseVehicle(..., 'vehicle.drive')` gate, enabling rank-approved family helicopter calls without weakening ownership checks.
- The optional vehicle type is forwarded to persistent creation so helipads create helicopters through the correct server vehicle type.
