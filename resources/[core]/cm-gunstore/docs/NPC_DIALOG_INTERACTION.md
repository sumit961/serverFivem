NPC DIALOG INTERACTION
======================

This update changes player shop opening flow:

1. Each gun store NPC gets a random name from Config.Ped.names when the resource starts.
2. The name is drawn above the NPC head when the player is nearby.
3. When the player is close enough, the head text also shows [E] Talk.
4. Pressing E opens a small dialog:
   - "Show me what you have got" opens the gun store catalog.
   - "No thanks" closes the dialog and does not open the store.

Config options added in shared/config.lua:
- Config.Ped.showName
- Config.Ped.nameHeight
- Config.Ped.nameDistance
- Config.Ped.names
- Config.Ped.dialog.title
- Config.Ped.dialog.optionStore
- Config.Ped.dialog.optionClose
