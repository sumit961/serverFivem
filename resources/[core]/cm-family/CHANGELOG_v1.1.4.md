# cm-family v1.1.4

- Fixed invitations being shown client-side before a valid database row existed.
- Invitation expiry now uses MariaDB `NOW()` consistently instead of the server OS timezone.
- Accept/decline resolves invitations by `family_id + character_id`, with legacy invite-ID fallback.
- Added support for non-AUTO_INCREMENT numeric or text `cm_family_invites.id` columns.
- Removed the ping check that suppressed ACKs for players reporting ping 0.
- Added guaranteed ox_lib success/error notifications and server failure diagnostics.
- Membership state is synchronized before the acceptance ACK.
