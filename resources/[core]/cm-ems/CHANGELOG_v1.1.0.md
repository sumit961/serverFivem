# cm-ems v1.1.0

- Added dynamic EMS rank creation, editing, and deletion.
- Added `ems.manage_ranks` and `ems.manage_permissions` authority.
- Added server-side tier limits and permission-subset validation.
- Protected the unique EMS leader rank from member management.
- Prevented deletion of ranks that still have members.
- Existing promotion and demotion flows now follow the customized rank order.
