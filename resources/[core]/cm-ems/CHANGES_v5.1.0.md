# cm-ems v5.1.0 — Medicine Stock & Supply Run

## Fixed
- Removed invalid `PlaceEntityOnGroundProperly` calls from mission patient placement.
- Outdoor mission patients now use `GetGroundZFor_3dCoord`; MLO patients keep their authored Z coordinate.
- Patient catch-up no longer crashes when escort pathfinding fails.

## Shared medicine stock
- Added one server-authoritative stock pool used by:
  - `cm-doctor` pharmacy purchases.
  - On-duty EMS G-menu medicine sales.
- Atomic SQL stock consumption prevents overselling.
- Failed inventory delivery/payment paths restore stock and money.
- Stock uses weighted units: bandage/painkillers/antibiotics 1, adrenaline 2, medkit 4.
- Low-stock EMS alert is sent at 40% or below.
- Added `/emsstock [0-100]` for authorized EMS admins and console testing.

## Medicine supply run
- Supply doctor: `301.5257, -579.6008, 28.8474, 279.7823`.
- Truck spawn/return: `365.0297, -569.6835, 28.8474, 242.9317`.
- Random Humane Labs loading point:
  - `3594.9790, 3661.8184, 33.8717`.
  - `3595.2209, 3669.8718, 33.8717`.
- Task is available only at 40% stock or below.
- Requires on-duty EMS and `ems.drive_ambulance`.
- Only one run may be active server-wide.
- Uses the supplied `cm-vehicles` trusted placement bridge and character-owned temporary access.
- Server validates assigned truck, driver seat, route stage and distance.
- Completion refills stock to 100%, pays bank reward, awards EMS XP and counts toward mission task progress.
- `/cancelmedrun` safely cancels and removes the assigned truck.

## Database
- Adds `cm_ems_medicine_stock`.
- Adds `cm_ems_medicine_runs`.
- Tables are created automatically; `sql/009_medicine_stock_v5.1.0.sql` is included for manual installation.
