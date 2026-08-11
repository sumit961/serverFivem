# cm-ems v5.9.0

- Mission patients visibly enter an authorized EMS vehicle and fall back to safe direct seating when custom vehicle door pathing fails.
- Patient loading must be confirmed locally before the server advances the shared mission stage.
- Built-in patient transport missions now finish with a server-validated ambulance-bay hospital handoff instead of requiring an indoor bed escort.
- Hospital handoff removes the mission patient after staff receive them; legacy unload and bed-delivery stages remain compatible.
- Mission Studio includes the new `hospital_handoff` stage for custom routes.
