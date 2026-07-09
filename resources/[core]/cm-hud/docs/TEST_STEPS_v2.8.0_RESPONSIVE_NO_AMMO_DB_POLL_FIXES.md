# Test Steps - CM HUD v2.8.0

1. Restart `cm-hud`.
2. Join with a character and confirm the HUD opens normally.
3. Watch server console for 1 minute and confirm `cm-hud` is not repeatedly querying character money every 2.5 seconds.
4. Change player money through the proper wallet/playerdata flow and call/confirm `exports['cm-hud']:RefreshCharacterHud(source, characterId)` updates the HUD.
5. Equip/switch weapons and confirm GTA's default ammo/weapon preview does not appear over the HUD.
6. Damage/kill the ped and confirm the death state triggers when GTA health reaches 100 or below.
7. Check right-middle voice/radio UI:
   - N key/glow for mic
   - O key/glow for family radio
   - U key/glow for org radio
   - no text labels `Mic`, `Family`, or `Org`
8. Test 1366x768, 1920x1080, and high-resolution/ultrawide display sizes if possible.
