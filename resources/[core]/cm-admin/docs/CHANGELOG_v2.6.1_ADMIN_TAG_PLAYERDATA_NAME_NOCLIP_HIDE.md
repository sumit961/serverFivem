# cm-admin v2.6.1 - Admin Tag Playerdata Name + Noclip Hide

## Changed
- Admin overhead tags now prefer `cm-playerdata` exports for character full name and character ID.
- Admin tag colour is now fully red for the whole overhead label.
- Admin overhead tags no longer draw for the local player.
- Admin overhead tags are hidden while the target admin is in noclip.
- If the viewer/admin is in noclip, admin overhead tags are not rendered on their screen.
- Noclip now reports a validated `cm_admin_noclip` statebag to the server so other resources can hide labels/interactions safely.

## Security / Performance
- The server validates `/admin` mode and `noclip` permission before replicating `cm_admin_noclip = true`.
- No server IDs are shown; tags still use database character ID only.
- No new heavy loops were added. Existing tag cache remains throttled.
