# cm-ems v5.0.1 — F6 organization dashboard fix

- Restores reliable F6 and `/ems` access to the organization-based EMS dashboard.
- Removes the client-side state-bag gate that could silently block valid members after a resource or character reload.
- Keeps membership authorization server-side and fail-closed for non-members.
- Opening the dashboard now repairs a missing or stale `cmEms` replicated state.
- F6 toggles the existing dashboard closed when it is already open.
