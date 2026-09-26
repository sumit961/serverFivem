# CM LAW v3.5.0 — Vehicle Enforcement Cleanup

- Routed handheld radar activation through server-authoritative Law membership, duty, suspension, capability, and permission checks. Kept the aim-based reading display-only, added the rendered registration to its compact hint, and cleaned up on death, duty changes, character unload, and resource stop.
- Unified Police and shared Law radar authorization without adding a second radar implementation.
- Hardened the patrol plate scanner: only authorized persistent organization fleet vehicles may scan, nearby candidates are bounded and server-validated, and duplicate BOLO alerts are suppressed.
- Added shared plate normalization and a cached active-BOLO lookup across the existing `cm_legal_bolos` and `cm_police_bolos` tables. Existing Police and generic storage remains intact; Law-wide matching follows the established fixed-camera sharing behavior.
- Kept fixed ALPR cameras as server-side infrastructure, matched normalized rendered registration values, identified issuing organizations in alerts, deduplicated recipients, and rate-limited repeated camera hits.
- Unified clamp authority and target validation. Clamps now require a persistent civilian-owned vehicle, same routing bucket, officer proximity, and an empty vehicle; server state prevents duplicate clamp props and cleanup removes props after entity deletion or resource stop.
- Updated shared and Police MDT vehicle lookup to accept public registration numbers, show active BOLO matches and preserve impound organization, reason, fee, and time fields.
- Preserved officer-decided enforcement. Radar and ALPR do not issue citations or fines; no traffic-stop or pursuit system was added.
