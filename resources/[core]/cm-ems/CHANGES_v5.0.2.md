# cm-ems v5.0.2 — mission stability fixes

- Cancelling a mission progress action now releases the server-side co-op objective lock immediately.
- Adds a server watchdog so abandoned objective locks expire safely after the configured action duration and grace period.
- Failed proximity checks and too-fast completions no longer leave a mission permanently locked.
- Reconstructs the local mission patient at the current route stage for medics who join late or reopen the dashboard.
- Transport and unload stages can recreate the patient inside a nearby authorized EMS vehicle.
- Adds patient catch-up safety for hospital doors, stairs and custom MLO pathfinding failures.
- Makes mission checkpoint interaction distances more forgiving while retaining server-side proximity validation.
- Adds clear on-screen hints when an EMS vehicle is missing or the medic is using an unauthorized vehicle.
