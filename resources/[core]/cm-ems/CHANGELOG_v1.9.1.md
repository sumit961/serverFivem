# cm-ems v1.9.1

- Keeps EMS fleet vehicles persistent by authoritative `vehicle_id`.
- Creates missing fleet entities through the proven `cm-house` client-assisted garage pipeline before promoting them into the world.
- Recalls an already-ready vehicle by moving the same entity and preserving its network identity.
- Safely replaces only an unoccupied, unverified legacy entity while retaining its database vehicle record.
- Uses the central EMS duty/rank access decision during persistent vehicle promotion.
