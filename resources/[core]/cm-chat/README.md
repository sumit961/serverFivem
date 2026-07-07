# cm-chat v1.2

Modular CM RP chat with cyan/blue UI.

## Main behavior

- Chat messages stay visible.
- Press `T` to open input, channel tabs, and actions.
- `RP` and `NON-RP` tabs are always visible.
- `FAMILY`, `ORG`, and `CLUB` tabs only show when the player has that group.
- `ADMIN` tab only shows for admin/staff.
- RP messages are proximity-only.
- NON-RP messages are global and are wrapped inside `(( message ))`.
- The message text does not show `[RP]` or `[NON-RP]` before the name.

## Message format

```txt
First Last (12) said: hello
First Last (12) said: (( hello ))
```

The sender prefix color comes from the channel color.

## Set family/org/club chat from another resource

```lua
exports['cm-chat']:SetPlayerChatGroup(source, 'family', familyId, 'green')
exports['cm-chat']:SetPlayerChatGroup(source, 'org', orgId, 'cyan')
exports['cm-chat']:SetPlayerChatGroup(source, 'club', clubId, 'purple')
```

You can also use hex colors:

```lua
exports['cm-chat']:SetPlayerChatGroup(source, 'family', familyId, '#72ff8c')
```

Multiple groups at once:

```lua
exports['cm-chat']:SetPlayerChatGroups(source, {
    family = { id = familyId, color = 'green' },
    org = { id = orgId, color = 'cyan' },
    club = { id = clubId, color = 'purple' }
})
```

## Move chat position

Edit `Config.UI` in `config.lua`:

```lua
Config.UI = {
    left = 24,
    top = 26,
    width = 720,
    height = 430,
    inputWidth = 600,
    fontSize = 18
}
```
