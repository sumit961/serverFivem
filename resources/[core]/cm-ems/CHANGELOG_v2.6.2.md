# v2.6.2

- Fixed the doctor becoming trapped against its own parked ambulance.
- Doctor/ambulance collision is disabled only for that entity pair while the medic exits and treats patients.
- The exit task now waits for the doctor to leave and uses GTA's forced-exit recovery only if the normal door path fails.
- Added a dedicated final CPR alignment step: the doctor must move within 1.8 metres and face the actual patient before starting the animation.
- A failed alignment is retried once instead of playing CPR beside the ambulance.
- Server-authoritative treatment distance was reduced from 5 metres to 2.25 metres, preventing a client from healing while the doctor is still near the truck.
