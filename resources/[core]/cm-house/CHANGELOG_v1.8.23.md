# cm-house v1.8.23

## Explicit family-garage registration

- Family-garage lists no longer include a member's personal vehicle solely because the owner belongs to the family.
- Family slot assignment, call, and store operations now require explicit family registration and preserve the registration when a vehicle changes location.
- Added authorized family registration exports while disabling the legacy owner-driven share callback/export path.
- Existing family registration rows and persistent `vehicle_id` identities remain supported.
