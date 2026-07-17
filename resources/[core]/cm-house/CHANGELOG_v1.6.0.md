# cm-house v1.6.0

## Garage-template creation

- Fixed standalone **New Garage** and re-walk capture so they use the real cyan
  placement car instead of only drawing a car-sized marker.
- Placement vehicles spawn in the layout creator's routing bucket.
- The creator is warped into the network vehicle when available.
- A local visible nudge-mode car is used only when the network vehicle cannot be
  created or streamed.
- Frozen placement examples and temporary vehicles are cleaned after save,
  cancellation, disconnect and resource stop.

## Multiple garage exits

- Reusable garage templates support up to the configured number of exits
  (`Config.GarageTemplate.maxVehicleExits`, default 8).
- The first exit remains in `vehicle_exit` for compatibility.
- The full ordered list is stored in `vehicle_exits`.
- Runtime selects the closest exit.
- The server validates the submitted exit index and vehicle proximity.
- No gameplay exit marker is drawn.
- The same exit works on foot or while driving.

## Parking customization point and anchors

Every new/re-walked garage captures:

- one fixed owner/family settings point;
- optional wall-wash anchors;
- optional light anchors;
- optional decor/prop anchors;
- real car parking slots.

## Per-property customization

Added owner/family-rank garage styling:

- theme presets;
- fixed floor/parking pads;
- wall light washes;
- ceiling/feature lighting;
- decor prop sets;
- accent colours;
- floor opacity;
- wall intensity;
- light intensity;
- decor density.

Selections are stored per house in `cm_house_garage_customizations` and broadcast
to every player inside that private garage.

## Security and integration

- Customization requires `garage.customize` server-side permission.
- Player must be inside the correct garage and near the saved settings point.
- All keys and fine-tuning values are allowlisted and clamped server-side.
- Added `GetGarageCustomization` and scoped `SetGarageCustomization` exports.
- Updated house/family capability contracts to v1.6.0 / 3.1.0.
