# cm-ems v2.2.2

- Moved temporary government ambulance and doctor creation to the server for OneSync/entity-lockdown compatibility.
- The caller client now selects a nearby road node and only controls the server-created network entities for driving and treatment.
- Added explicit model, creation, and streaming failure reporting so dispatches do not remain falsely assigned.
