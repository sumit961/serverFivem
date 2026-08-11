# cm-ems v5.0.3 - NPC Interaction Reliability

## Fixed

- Patient/NPC objectives now use the visible NPC as the interaction anchor instead of requiring the player to also stand on an invisible configured coordinate.
- Increased the practical NPC interaction range to 4.5 metres.
- Mission markers for treatment, recovery, patient pickup and ambulance loading now follow the visible patient.
- Added a direct E-key fallback so mission actions still work when another resource also maps E.
- Added clear blocking hints when the patient must be moved to a destination, an EMS vehicle is missing, or the medic is still inside a vehicle.
- Patient peds no longer drift away from treatment points while their injured/waiting animation plays.
- Indoor patient placement keeps the configured MLO Z coordinate instead of being snapped to an exterior floor below the hospital.
- Admin-created missions infer patient presentation from patient stage types even if the route-level patient option was not saved.

## Installation

No SQL migration is required. Replace the resource and restart `cm-ems`.
