# Test Steps - cm-admin v2.6.1

1. Restart `cm-playerdata` then `cm-admin`.
2. Join with an admin character and run `/admin`.
3. Ask another player to look at you. They should see a red overhead tag:
   - `Administrator`
   - your first/last character name from `cm-playerdata`
   - your database character ID only
4. Confirm you do not see your own admin tag.
5. Press F2 / use noclip.
6. Confirm your admin tag disappears for other players while noclip is active.
7. Confirm normal playerdata overhead labels/G-menu also ignore admins who are currently in noclip.
8. Disable noclip and confirm the red admin tag returns.
9. Run `/admin` again to leave admin mode and confirm the tag is removed.
