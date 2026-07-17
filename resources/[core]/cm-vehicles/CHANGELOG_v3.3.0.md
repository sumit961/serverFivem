# cm-vehicles v3.3.0 — Condition Integrity

- Separates temporary bootstrap health from real saved health.
- Numeric zero remains destroyed; invalid/missing data alone uses fallback.
- Applies and verifies full saved condition before marking an entity ready.
- Keeps failed initialization quarantined/undriveable and retries safely.
- Stops garage protection from writing health after initialization.
- Uses database vehicle ID as the authoritative spawn-registry key.
- Adds startup OneSync entity reconciliation and synchronous ID-based deletion.
- Blocks engine start until condition is ready and blocks damaged engines on both client and server.
- Adds rollback for failed public-parking spawns.
- Makes the old health repair SQL diagnostic-only.
