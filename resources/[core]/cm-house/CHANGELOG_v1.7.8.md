# cm-house v1.7.8

- Adds authorized `GetFamilyVehicleManagementList(familyId, ownerCid)` export.
- Returns family-shared cars plus the requesting owner's personal cars.
- Marks whether a car is parked in the authoritative family garage and is eligible for sharing.
- Does not expose another member's private vehicle list.
- Existing owner-only `SetVehicleFamilyShared` validation remains authoritative.
