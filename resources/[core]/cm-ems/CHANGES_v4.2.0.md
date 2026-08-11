# cm-ems v4.2.0 — career, transport and call history

- Adds persistent EMS XP and six career levels without changing organization rank or permissions.
- Awards anti-farm XP for unique dispatch responses, revives and medical reports.
- Shows career level, title, XP and next-level progress in Employee Tasks.
- Adds synchronized stretchers: J deploy/store, E push/release/load/unload, and G-menu patient placement/removal.
- Allows only on-duty employees with treatment permission to control stretchers.
- Adds an 8-second mobile treatment flow for X-key EMS treatment; moving outside the patient radius cancels completion.
- Shows the treating medic's name in conscious-player Y/N requests and gives both players treatment progress feedback.
- Adds persistent incident timeline events for creation, acceptance, status, arrival, AI assignment, clearing and resolution.
- Expands F10 dispatch history with responders, acceptance time, scene arrival, closure time, outcome and timeline.
- Creates new database tables automatically; `sql/006_career_transport_history_v4.2.0.sql` is included for manual installs.
