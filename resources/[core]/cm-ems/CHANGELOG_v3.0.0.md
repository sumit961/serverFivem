# cm-ems v3.0.0

- Added a server-owned government response state machine: waiting, driving, parked, treating, waiting nearby, departing, and cleanup.
- Government doctors now receive their next patient from the server, prioritized by shortest bleed-out time, then distance, then oldest call.
- CPR completion now waits for a server treatment acknowledgment. Failed position/heal validation keeps the patient assigned and retries after a short backoff.
- A nearby active government response claims both existing and newly-created calls without spawning a second ambulance.
- AI assignments protect the patient's death timer through the `cm-playerdata` medical-response contract and provide an arrival countdown.
- Shared response failures release every linked order safely so no patient remains locked to a dead response.

Install this together with `cm-playerdata` v1.10.0-ems-protection or newer.
