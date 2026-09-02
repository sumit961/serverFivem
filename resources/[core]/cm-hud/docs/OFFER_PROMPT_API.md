# Shared offer prompt API

`cm-hud` owns presentation only. The calling resource must retain its pending
offer, validate expiry/permissions/distance server-side, and handle its own Y/N
key mappings and response event.

```lua
exports['cm-hud']:ShowOffer({
    id = 'family-invite:' .. inviteId,
    eyebrow = 'FAMILY INVITATION',
    title = 'Do you want to join Northside?',
    sender = inviterName,
    senderId = inviterCharacterId, -- character ID only; never FiveM source
    distance = '2.4 M',
    icon = 'invite', -- offer | invite | medical | property | vehicle
    acceptKey = 'Y', acceptText = 'Accept',
    declineKey = 'N', declineText = 'Decline',
    duration = 15000,
})

exports['cm-hud']:HideOffer('family-invite:' .. inviteId)
```

Equivalent local client events are available:

- `cm-hud:client:showOffer`
- `cm-hud:client:hideOffer`

Showing another offer replaces the currently visible prompt. Hiding with a
non-matching ID does not dismiss the active offer.
