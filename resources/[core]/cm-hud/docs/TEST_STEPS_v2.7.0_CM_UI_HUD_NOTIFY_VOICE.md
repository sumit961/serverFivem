# Test steps - cm-hud v2.7.0

1. Confirm `server.cfg` starts `cm-ui` before `cm-hud`.
2. Restart in this order:
   ```cfg
   restart cm-ui
   restart cm-core
   restart cm-auth
   restart cm-playerdata
   restart cm-characters
   restart cm-climatime
   restart cm-spawn
   restart cm-hud
   ```
3. Join and spawn. Confirm HUD appears with the larger default scale.
4. Confirm location sits with default values: X `-7`, Y `-112`.
5. Run `/hud admin` and confirm the UI still opens and settings save.
6. Run `/hud reset` if old local KVP settings appear wrong.
7. Test notifications:
   ```lua
   TriggerEvent('cm-hud:client:notify', 'Cyan info test', 'info')
   TriggerEvent('cm-hud:client:notify', 'Green success test', 'success')
   TriggerEvent('cm-hud:client:notify', 'Red error test', 'error')
   ```
8. Hold `N`; the mic indicator should glow.
9. Hold `O`; the family radio indicator should glow.
10. Hold `U`; the organization radio indicator should glow.
11. Enter/exit a vehicle and confirm speedometer, seatbelt, and time still work.
12. Confirm the F8 console is quiet and there is no NUI spam while holding no keys.
