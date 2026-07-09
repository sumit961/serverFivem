# CM HUD v2.8.0 - Responsive HUD + No Ammo Preview + Performance Fixes

## Changed
- Removed the constant server-side DB polling loop that queried money every 2.5 seconds for every online player.
- Money HUD is now event/export driven through `exports['cm-hud']:RefreshCharacterHud(source, characterId)`.
- Fixed safe character ID extraction in `sendCharacterHud` so a Lua table cannot become a SQL parameter like `table: 0x...`.
- Fixed client death detection to treat GTA ped health `<= 100` as dead.
- Added a lightweight client frame guard to hide GTA default weapon/ammo preview components while the CM HUD is visible.
- Removed text labels `Mic`, `Family`, and `Org` from the right-middle voice/radio indicators.
- Kept N/O/U key + icon indicators and glow behaviour.
- Added extra responsive scaling rules for lower resolutions, ultrawide, high-res, and short-height screens.

## Notes
- This resource still does not show FiveM server ID to players. The top-right ID remains the database character ID supplied by playerdata/characters.
- No gameplay logic was moved into the HUD.
