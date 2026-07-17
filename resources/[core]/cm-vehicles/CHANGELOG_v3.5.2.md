# cm-vehicles v3.5.2 — Garage spawn convergence

- Extends client-assisted garage creation timeout from 12 to 30 seconds.
- Marks provisional entities with their database vehicle ID for authoritative reconciliation.
- Explicitly rejects timed-out client creations instead of leaving quarantined ghosts.
- Retries rejected network-entity deletion for five seconds during ownership migration.
