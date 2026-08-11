# CM EMS 5.5.1

- Automatically takes an on-duty EMS member off duty when the authoritative
  player death lifecycle marks them incapacitated.
- Uses the same cleanup lifecycle for manual off-duty, character unload, and
  disconnect.
- Clears dispatch assignments and GPS, active mission participation, treatment
  offers/progress, medicine supply runs and their temporary vehicle, and owned
  stretchers.
- Transfers mission leadership to another on-duty participant when possible;
  otherwise cancels the mission safely.
- Preserves persistent EMS fleet vehicles during cleanup.
