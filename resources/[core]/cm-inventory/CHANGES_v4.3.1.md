# CM Inventory v4.3.1 fixes

- Disabled GTA weapon wheel, native weapon slot switching, mouse-wheel weapon cycling, and native reload while inventory is closed.
- Keys 1-5 now reliably trigger CM fast-access slots without timing-sensitive polling.
- Added local death detection plus server deduplication; equipped gun and ammo-slot stack drop once as normal world pickups.
- Fixed identical clothing stacking even when cm-items marks clothing as unique/non-stackable. Appearance metadata must still match.
- Drop and give actions transfer the full stack without an amount prompt.
- Give flow shows nearby character names, a player list when several are nearby, and requires confirmation.
- Ctrl + right-click moves an item to the other open vehicle/stash/container; no open second container means no action. Double-right-click remains supported.
- Removing a gun from the weapon slot moves equipped ammo back to normal inventory when space is available.
- Removed timing-sensitive idle weapon-control polling that could miss key presses and allow GTA weapon selection.
