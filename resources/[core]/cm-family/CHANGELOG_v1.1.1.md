# cm-family v1.1.1

- Fixed `Duplicate entry '' for key PRIMARY` when accepting invites on legacy `cm_family_members` tables whose `id` column is not AUTO_INCREMENT.
- Added schema-aware member insertion for current, id-less, legacy text-id, and legacy numeric-id member tables.
- Founder creation and invite acceptance now use the same safe insertion path.
- Invitations are not deleted until membership insertion succeeds.
- Added immediate top-screen family invite prompt: Y accepts, N declines.
- Added configurable invite expiry and prompt duration.
- Added response locking and expiry validation.
