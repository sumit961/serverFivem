# v2.4.0

- Government EMS now dispatches automatically only when no authorized EMS player is on duty.
- On-duty EMS can still explicitly send a government doctor from dispatch.
- AI retries re-check live EMS duty coverage before automatically sending another NPC.
- Ambulance spawn candidates now require a clear road volume, loaded collision, and a verified nearby ground height.
- AI route retries wait for the previous ambulance cleanup instead of being silently dropped.
- Government treatment now uses the same authoritative full patch/heal path as live EMS treatment.
