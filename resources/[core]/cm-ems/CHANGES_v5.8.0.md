# cm-ems v5.8.0

- Treatment cancellation now clears the medic animation/progress immediately,
  including disconnect, off-duty, distance, incapacitation, and vehicle-entry
  paths.
- Dispatch routing now tracks the routed call separately so another call being
  cleared cannot remove the active GPS route.
- Direct ambulance loading is confirmed after the patient is actually seated.
- Added a server-validated remove-from-ambulance interaction for stopped EMS
  ambulances.
- Pharmacy purchases now have a short per-player anti-duplication guard.
