# Central prison intake

CM Law 2.7 routes every legal organization through the single `cm-prison`
intake NPC. SAHP, Sheriff, FIB, Army, and the embedded Police booking flow
share the same intake coordinate, cell spawn pool, release point, and prison
sentence authority.

Per-organization intake facilities are no longer registered or spawned. Old
`cm_legal_facilities` intake rows are ignored safely. Existing shared jail
spawn and release settings are migrated by cm-prison when its settings table
is created.

Start `cm-prison` before `cm-law`. Configure the intake NPC once from the
existing Police prison admin control; configure cell spawns and the release
point there or through the shared jail controls. No intake location is needed
for each law organization.

The F6 overview now shows central prison readiness, occupied capacity, and
spawn-point count. The Daily Desk also includes a custody-readiness check so
officers can verify the shared system at the start of each shift.

The F6 dashboard also includes a permission-gated Custody tab. Authorized,
on-duty officers can view the live shared prisoner list, booking reason,
booking officer, sentence duration, and a continuously updating release timer.
