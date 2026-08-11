# v2.6.0

- Nearby ambulance calls within 40 metres and the same routing bucket now share one government doctor.
- The doctor keeps a server-authorized patient queue, patches each still-downed caller, and resolves every dispatch separately.
- A second ambulance is no longer spawned for a caller already covered by a nearby active government response.
- Departure cleanup now collects visibility reports from every connected player in the routing bucket.
- The ambulance and doctor remain while any player can see either entity, then delete after both stay out of sight for 2.5 seconds.
- There is no visible-time timeout: the entities remain for as long as at least one player can still see them.
