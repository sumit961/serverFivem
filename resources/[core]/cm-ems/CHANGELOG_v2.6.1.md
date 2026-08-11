# v2.6.1

- Fixed a shared AI response treating only the first of two nearby downed callers.
- The server-authorized dispatch queue is now authoritative for remote patients instead of relying on potentially stale remote death statebags.
- Added a short streaming wait when a queued nearby patient ped is not immediately available.
- Fixed the doctor returning to the ambulance but leaving it parked permanently.
- Departure now reacquires entity control, allows the natural entry animation, safely recovers into the driver seat if needed, and verifies that the drive-away task starts.
- A stopped departure is retasked and finally falls back to normal ambient driving before all-player visibility cleanup begins.
