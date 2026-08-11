# cm-ems v4.1.0 — employee tasks

- Adds rank-aware daily and weekly EMS employee objectives.
- Tracks real on-duty minutes, unique dispatch responses, unique patient revives and manual medical reports.
- Adds an EMS Tasks dashboard with progress bars and individual bank-reward claims.
- Daily progress resets at server midnight; weekly progress resets each Monday.
- Uses unique incident, patient-death and report keys to prevent repeat farming.
- Rewards are claimed atomically and safely restored if bank payment fails.
- Task definitions, goals, labels and rewards are configurable in `shared/config.lua`.
