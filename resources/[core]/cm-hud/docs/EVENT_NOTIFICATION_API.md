# Event notification API

Client resources can show the reusable CM event announcement with:

```lua
exports['cm-hud']:ShowEventNotification({
    id = 'event-instance-id',
    eyebrow = 'EVENT STARTING',
    title = 'EVENT NAME',
    subtitle = 'Event area or short description',
    startsAt = os.time() + 60,
    duration = 7000,
    primaryKey = 'E',
    primaryText = 'JOIN AT EVENT EDGE',
    secondaryKey = 'GPS',
    secondaryText = 'ROUTE SET',
    accent = '#4fd1ff'
})
```

The export is client-local and presentation-only. The resource that owns an
event must decide eligibility on the server before sending an event-specific
message to a client. Displaying this notification does not grant entry,
permissions, rewards, routing-bucket access, or any other gameplay state.

Text is length-limited, accent colors require six-digit hex format, and the
visible duration is clamped between 3 and 60 seconds so short event notices and
time-limited result prompts can share the same compact surface.
