# cm-ems v1.9.0

- Converts configured EMS fleet entries to permanent `cm-vehicles` records with authoritative `vehicle_id` values.
- Adds a separate Set location edit mode that creates a temporary dummy, saves its server-observed position on H, then deletes the dummy.
- Calls and recalls reuse the same persistent vehicle record and duplicate-safe `cm-vehicles` spawn registry.
- Adds Recall all, explicitly servicing successful recalls to full fuel, full engine/body/tank health and zero dirt.
- Protects EMS fleet vehicles from sale, deletion, key management and family sharing through the `cm-vehicles` access decision.
- Replaces current-outfit presets with the `nv_cloth` EMS wardrobe and EMS catalogue editor.
- Going on or off duty no longer overwrites the character's clothing.
