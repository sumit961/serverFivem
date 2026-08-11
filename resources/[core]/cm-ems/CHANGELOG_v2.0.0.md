# cm-ems v2.0.0

- Added server-authoritative ambulance requests with `/ambulance [details]`.
- Added the `CreateAmbulanceCall(source, details)` server export for future phone integration.
- Only currently on-duty EMS members receive dispatch cards and map blips.
- Added Y-to-respond waypoint assignment and dispatch acceptance activity logs.
- Recreated the supplied Unique Dispatch card UI locally without QBCore/ESX or external CDN dependencies.
