# v2.5.0

- Fixed the government ambulance remaining frozen until a player moved close to it.
- AI EMS now spawns on a clear, preferably out-of-view road 55-100 metres from the patient, inside GTA's active NPC simulation range.
- Removed reliance on long-distance AI simulation and teleport-style approach behaviour.
- The driver now receives reliable network migration, mission, non-fleeing, and persistent-task settings.
- A response that cannot acquire entity control fails quickly and retries from a fresh safe route.
- Server spawn validation now matches the safe relaxed road-node search instead of silently dropping a valid response.
- Response timing is now faster, and the ambulance drives away before out-of-sight cleanup like ambient GTA emergency services.
