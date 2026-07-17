# cm-family ↔ cm-chat integration v1.1.8

`cm-family` owns family membership, rank permission `chat.family`, sender identity,
message cooldown, and the initial online-member set. `cm-chat` owns rendering,
the FAMILY tab, chat history/logging, and a second recipient validation pass.

## Send paths

- Select the FAMILY tab and submit a message.
- Use `/f message`.
- Use `/familychat message`.

All three paths call `exports['cm-family']:SendFamilyChat(...)`.

## Server-only delivery event

`cm-family` emits:

```lua
TriggerEvent('cm-chat:server:familyMessage', payload, recipients)
```

`cm-chat` intentionally uses `AddEventHandler`, not `RegisterNetEvent`, so a
client cannot forge this delivery event. It verifies the sender's replicated
`cmFamily` state and rebuilds online recipients with the same family ID.

## Display

```text
[TAG] [Rank or custom title] Character Name (CID): message
```

The family colour controls the FAMILY tab and message accent.
