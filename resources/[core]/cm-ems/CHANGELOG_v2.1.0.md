# cm-ems v2.1.0

- Added `ems.receive_dispatch` and `ems.manage_dispatch` rank permissions.
- Dispatch notifications are sent only to authorized on-duty EMS members.
- Added an F10 emergency-call board with caller, location, status, live distance and assignment state.
- Calls can be claimed by one medic; competing claims fail closed and all dispatch users receive the updated assignment.
- Authorized managers can remove calls from the board.
- Added safe one-time default grants for Chief Paramedic and Paramedic ranks through `cm_ems_migrations`.
