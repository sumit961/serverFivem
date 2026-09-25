# cm-law v3.3.2

- Simplified generic and Police Fleet panels to show vehicle image, name, required rank and status to regular members.
- Added organization-scoped named-rank selectors. Server updates now validate the selected tier against the organization's authoritative rank table and keep `min_tier` unchanged.
- Made generic Fleet manager checks consistent and added Police leader management parity when stored permission JSON omits `police.manage_vehicles`.
- Kept `law.vehicle` and `police.spawn_vehicles` as backwards-compatible keys, with their labels and internal meaning updated to fleet vehicle use.
- Removed unused client/NUI manual Fleet Spawn relays while retaining server rejection callbacks for compatibility.
- Preserved the existing persistent vehicle, recovery, H-key parking, recall, tuning and Vehicle G-menu contracts. No database migration or gameplay feature expansion.
