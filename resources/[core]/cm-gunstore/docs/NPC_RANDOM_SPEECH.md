NPC RANDOM SPEECH
=================

Added random NPC speech for gun store clerks.

Behavior:
- When a player walks near a gun store NPC, the clerk shows one random greeting line above their head.
- The greeting has a cooldown so it does not spam every second.
- When the player chooses "No thanks" in the dialog, the NPC says one random goodbye line.
- The player can still press E while the speech text is showing.

Edit lines in shared/config.lua:

Config.Ped.greetings = { ... }
Config.Ped.farewells = { ... }

Useful settings:
- Config.Ped.speechDistance
- Config.Ped.speechDuration
- Config.Ped.speechCooldown
