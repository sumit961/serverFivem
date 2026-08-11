# cm-ems v4.3.0 — selectable EMS missions

- Moves persistent call history from F10 into `/ems` > Call History.
- F10 now contains only active and assigned live dispatch calls.
- Adds a selectable mission board inside `/ems` > Employee Tasks.
- Adds medical supply, urgent medicine, roadside rescue, water rescue, mountain rescue, hospital transfer and fleet repair-response missions.
- Starting a mission closes the EMS menu, creates a GPS route and activates staged E interactions.
- Rescue and transfer missions create a visible local patient and load them into the medic's ambulance or helicopter.
- Server validates on-duty membership, objective proximity, stage timing, active mission ownership and authorized transport vehicles.
- Rewards are deposited to bank and award EMS career XP only after server-confirmed completion.
- Adds per-mission cooldowns, cancellation, timed urgent missions and restart/disconnect cleanup.
- Mission completion contributes to new daily and weekly EMS objectives.
- All mission definitions, routes, stages, rewards, XP and cooldowns are configurable in `shared/config.lua`.
