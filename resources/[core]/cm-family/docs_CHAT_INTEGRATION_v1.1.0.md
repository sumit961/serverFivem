# cm-chat integration contract

cm-family sends family messages itself and also emits these server events:

```lua
AddEventHandler('cm-family:server:chatMessage', function(payload, recipients)
    -- payload.familyId
    -- payload.familyName
    -- payload.tag
    -- payload.color
    -- payload.characterId
    -- payload.name
    -- payload.rankName
    -- payload.title
    -- payload.message
    -- recipients = array of server sources in the same family
end)
```

Compatibility alias:

```lua
AddEventHandler('cm-chat:server:familyMessage', function(payload, recipients)
end)
```

A future cm-chat family tab should consume one of these server events. Do not
trust a client-supplied family id or recipient list. cm-family has already
resolved both on the server.
