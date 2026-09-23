# CM HUD reusable components

`cm-hud` owns presentation. The resource that owns an event, offer, or timer
must still decide who is eligible, when it expires, and what happens next.
These APIs only display information; they do not grant permission or perform
gameplay actions.

## Event announcement

```lua
exports['cm-hud']:ShowEventNotification({
    id = 'city-meetup-2026-09-21',
    eyebrow = 'CITY-WIDE EVENT',
    title = 'Midnight Meetup',
    subtitle = 'Meet at the Del Perro pier.',
    startsAt = os.time() + 120, -- Unix seconds; optional
    duration = 9000, -- milliseconds, clamped to 3-60 seconds
    primaryKey = 'G',
    primaryText = 'Set GPS',
    secondaryKey = 'F',
    secondaryText = 'Join event',
    accent = '#00E5FF' -- optional six-digit hex
})
```

The event owner sends this only to eligible clients. Optional `image` and
`notificationKey` values are also supported. Text and image values are
length-limited by the HUD client.

## Countdown timer

```lua
exports['cm-hud']:SetHudTimer({
    id = 'rental',
    title = 'RENTAL IDLE LIMIT',
    label = 'Drive the rental again before it expires',
    durationMs = 120000,
    tone = 'warning' -- info, success, warning, danger
})

exports['cm-hud']:ClearHudTimer('rental')
```

Timers use a local display countdown from `durationMs` (1 second to 24 hours).
The owning resource must issue an updated duration when the authoritative
remaining time changes. Setting the timer again with the same `id` replaces
its current display card. The same methods are available as local events:
`cm-hud:client:setTimer` and `cm-hud:client:clearTimer`.

`cm-hud` consumes `cm-taxi:client:rentalIdleTimer` automatically and shows the
shared rental card during the taxi rental's server-issued idle grace period.
The taxi resource remains responsible for rental expiry and vehicle cleanup.

## Layout preview

`/hud preview` and `/hudshowall` toggle sample values for all HUD elements,
including event and offer cards, notifications, and the rental countdown.
The preview is client-side only and does not save settings or issue gameplay
requests.
