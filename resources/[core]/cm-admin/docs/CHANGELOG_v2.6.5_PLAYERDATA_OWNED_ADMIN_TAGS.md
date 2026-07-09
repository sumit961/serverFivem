# CM Admin v2.6.5 - Playerdata Owned Admin Tags

## Changes
- Disabled the old separate cm-admin overhead tag renderer by default.
- cm-admin still sets `cm_admin_tag` and `cm_admin_noclip` statebags.
- cm-playerdata now owns the actual overhead label drawing, so admin mode replaces the normal name/ID label instead of drawing a second admin label.
- Existing admin map, logs, permissions, GPS TP, noclip and calibration UI are unchanged.

## Why
The server should have only one overhead label system. Normal player labels and admin labels are now drawn by cm-playerdata using the same anchoring and database character ID rules.
