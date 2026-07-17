# CM Chat

`cm-chat` is the CM Framework roleplay chat resource. It replaces the normal
FiveM text-chat UI with an always-visible message feed and a configurable NUI
for RP, global, group, and staff channels.

This document describes version `1.4.0`, matching `fxmanifest.lua`.

## Contents

- [How it works](#how-it-works)
- [Installation and start order](#installation-and-start-order)
- [Player controls](#player-controls)
- [Channels](#channels)
- [Commands](#commands)
- [Configuration](#configuration)
- [Character integration](#character-integration)
- [Family, organisation, club, and custom groups](#family-organisation-club-and-custom-groups)
- [Developer API](#developer-api)
- [Admin permissions and announcements](#admin-permissions-and-announcements)
- [Database logging](#database-logging)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

## How it works

1. The client waits until a character is logged in and resolves the active
   character ID from CM events or player state.
2. The server resolves the character's first and last name from the configured
   character table, unless another resource supplied the name directly.
3. Pressing `T` opens the NUI. The server sends only the channel tabs that the
   player is allowed to see.
4. The server cleans and rate-limits each message, checks blocked words and
   channel access, chooses the recipients, and optionally logs the message.
5. Nearby channels use server-side player coordinates. Group channels only go
   to players with the same group value. Staff chat only goes to staff.
6. The NUI escapes message content before rendering it. Messages remain visible
   while input is closed, up to `Config.MaxVisibleMessages`.

Messages are held in the client's NUI memory. `/clear`, a resource restart, or
reconnecting clears that local feed.

## Installation and start order

Keep the resource directory named `cm-chat` and start it after the CM character
resources. `oxmysql` is optional for message delivery, but it is required for
database name lookup and chat logging. OneSync is required for reliable
server-side proximity routing. Resources that call CM Chat exports must start
after `cm-chat`.

```cfg
ensure oxmysql
ensure cm-core
ensure cm-playerdata
ensure cm-characters
ensure cm-spawn
ensure cm-chat
```

Do not run another custom chat UI at the same time. `cm-chat` disables the
native text chat while it is active and restores it when the resource stops.

After changing `config.lua`, restart the resource:

```text
restart cm-chat
```

## Player controls

| Control | Result |
| --- | --- |
| `T` | Open chat using the configured `Config.OpenKey` |
| `/cmchat` | Open chat from a command |
| Click a channel tab | Select where a normal message will be sent |
| `Enter` | Send the current message |
| `Escape` or click outside | Close chat without sending |
| `Arrow Up` / `Arrow Down` | Browse up to 40 messages from the current session |
| `ACTIONS` | Insert an RP command such as `/me`, `/do`, or `/try` |

Typing text without a leading slash sends it to the selected tab. Typing text
that starts with `/` runs it as a FiveM command.

The chat cannot open until the client is marked as logged in. It also refuses
to take focus while another NUI already owns focus.

## Authoritative family channel

When `cm-family` is running, the FAMILY tab is derived from the replicated `cmFamily` player state. Messages selected through the FAMILY tab are sent through `cm-family`, so rank permission `chat.family`, cooldowns, family membership, tags, colours, titles, and recipient selection remain authoritative. The displayed format is `[TAG] [Rank or Title] Character Name (CID): message`. `/f` and `/familychat` use the same path.

## Channels

| Channel | Audience | Default behaviour |
| --- | --- | --- |
| `RP` | Players within 20 metres | `First Last (ID) said: message` |
| `NON-RP` | Every player | Wraps the message as `(( message ))` |
| `FAMILY` | Players with the same family value | Visible only to family members |
| `ORG` | Players with the same organisation value | Visible only to organisation members |
| `CLUB` | Players with the same club value | Visible only to club members |
| `ADMIN` | Staff players only | Visible only when staff access is detected |

The following hidden channels render messages but do not appear as selectable
tabs: `ME`, `DO`, `LOW`, `SHOUT`, `ACTION`, admin announcements, and admin
system actions.

Channel types supported by the server are:

- `proximity`: recipients must be within the configured radius.
- `global`: every connected player receives the message.
- `group`: recipients must have the same value for the channel's group.
- `staff`: recipients must pass the staff check.

## Commands

| Command | Range/audience | Purpose |
| --- | --- | --- |
| `/me <text>` | 20 metres | Character action, displayed as `* text` |
| `/do <text>` | 20 metres | Describes the scene |
| `/try <text>` | 20 metres | Adds a random `success` or `fail` result |
| `/ooc <text>` | Global | NON-RP message |
| `/b <text>` | 5 metres | Local NON-RP message |
| `/low <text>` | 5 metres | Quiet local RP speech |
| `/s <text>` | 35 metres | Shout |
| `/shout <text>` | 35 metres | Shout alias |
| `/a <text>` | Staff only | Staff chat |
| `/staff <text>` | Staff only | Staff-chat alias |
| `/clear` | Current player only | Clears the local message feed |
| `/announce <text>` | Global, permission required | Named admin announcement |
| `/anon <text>` | Global, permission required | Anonymous admin announcement |

There are no `/rp`, `/nonrp`, `/family`, `/org`, `/club`, or `/admin` commands;
those destinations are selected with the UI tabs.

## Configuration

All normal settings are in `config.lua`.

### Limits and UI

```lua
Config.OpenKey = 'T'
Config.MaxMessageLength = 180
Config.ChatCooldownMs = 650
Config.DefaultLocalRadius = 20.0
Config.MaxVisibleMessages = 45

Config.UI = {
    left = 24,
    top = 26,
    width = 720,
    height = 430,
    inputWidth = 600,
    fontSize = 18
}
```

Numeric UI values are treated as pixels. CSS-compatible strings can also be
used, for example `width = '38vw'`. The current NUI itself has a hard maximum of
180 characters, so raising `Config.MaxMessageLength` above 180 does not increase
the effective client limit without also changing `ui/app.js`.

### Blocked words

```lua
Config.EnableBlockedWords = true
Config.BlockedWords = {
    'blocked phrase',
    'another phrase'
}
```

Matching is case-insensitive and checks for a literal substring. A blocked
message is not sent and the player receives `Message blocked.`

### Actions and channel layout

`Config.Actions` controls the quick-action buttons. `Config.ChannelOrder`
controls tab order. `Config.Channels` controls labels, colours, routing type,
range, format, and visibility.

```lua
Config.Actions = {
    { id = 'me', label = 'ME', command = '/me ' },
    { id = 'do', label = 'DO', command = '/do ' }
}
```

Supported named colours are declared in `Config.ColorPalette`. A three-, six-,
or eight-digit hexadecimal colour can also be supplied.

## Character integration

CM Chat already listens for the character-loaded events emitted by `cm-core`,
`cm-playerdata`, `cm-characters`, and `cm-spawn`. It also reads common character
ID keys from the player state bag.

The configured lookup schema is:

```lua
Config.CharacterTable = 'characters'
Config.CharacterIdColumn = 'id'
Config.CharacterFirstNameColumn = 'first_name'
Config.CharacterLastNameColumn = 'last_name'
```

For a different framework, set the login state and provide the character from
server-side code:

```lua
local src = source
Player(src).state:set('isLoggedIn', true, true)

-- Supplying the name avoids a database lookup.
exports['cm-chat']:SetPlayerCharacter(src, characterId, 'First Last')
```

If the third argument is omitted, CM Chat queries the configured character
table for the name.

On character logout, the normal `cm-playerdata:client:unloaded` event closes the
UI and clears the cached character and group data.

## Family, organisation, club, and custom groups

Group membership can come from a state bag or from a server export. The export
is recommended because it refreshes the player's channel tabs immediately.

### Set one group

```lua
exports['cm-chat']:SetPlayerChatGroup(source, 'family', familyId, 'green')
exports['cm-chat']:SetPlayerChatGroup(source, 'org', organisationId, 'cyan')
exports['cm-chat']:SetPlayerChatGroup(source, 'club', clubId, '#b889ff')
```

Set the group value to `nil`, an empty string, or `false` to remove access:

```lua
exports['cm-chat']:SetPlayerChatGroup(source, 'family', nil)
```

### Set several groups

```lua
exports['cm-chat']:SetPlayerChatGroups(source, {
    family = { id = familyId, color = 'green' },
    org = { id = organisationId, color = 'cyan' },
    club = { id = clubId, color = 'purple' }
})
```

The value may also be named `value`, `groupId`, `group_id`, or `name`. The colour
may be named `color`, `chatColor`, or `chat_color`.

### State-bag alternative

The default state keys are listed in `Config.GroupStateKeys`, including
`familyId`, `orgId`, and `clubId` plus their common variants.

```lua
Player(source).state:set('familyId', familyId, true)
```

State-bag changes are picked up the next time channels are requested, normally
when the player opens chat. Use `SetPlayerChatGroup` when an immediate tab
refresh is important. Updating family or organisation metadata in
`cm-playerdata` does not currently populate these chat state keys by itself;
the resource that changes membership should also call the CM Chat export.

## Developer API

All exports below are server exports.

### `SetPlayerChatGroup`

```lua
local ok = exports['cm-chat']:SetPlayerChatGroup(
    playerSource,
    'family',
    familyId,
    'green'
)
```

Returns `true` when the input is accepted.

### `SetPlayerChatGroups`

```lua
local ok = exports['cm-chat']:SetPlayerChatGroups(playerSource, groups)
```

Sets multiple group values and returns `true` when the input is accepted.

### `SetPlayerCharacter`

```lua
local ok = exports['cm-chat']:SetPlayerCharacter(playerSource, characterId, characterName)
```

The name is optional. Omitting it causes a database lookup.

### `RegisterChatChannel`

Register a channel without editing CM Chat:

```lua
exports['cm-chat']:RegisterChatChannel('job', 'JOB', {
    type = 'group',
    group = 'job',
    color = 'blue',
    format = 'group'
})

exports['cm-chat']:SetPlayerChatGroup(source, 'job', 'police', 'blue')
```

Supported options are `type`, `group`, `global`, `radius`, `staff`, `always`,
`hiddenTab`, `color`, and `format`. A global or proximity channel needs
`always = true` to appear as a tab for everyone. Newly registered tabs appear
the next time a player requests channels or opens chat.

### `BroadcastChatMessage`

```lua
exports['cm-chat']:BroadcastChatMessage(
    channelId,
    authorName,
    authorCharacterId,
    text,
    targets,
    sourcePlayer,
    formatOverride
)
```

- `targets` may be one server ID, a table of server IDs, or `nil`.
- With `targets = nil`, the registered channel decides how recipients are
  selected.
- A proximity or group broadcast needs `sourcePlayer` so the server can resolve
  distance or group membership.

Example targeted message:

```lua
exports['cm-chat']:BroadcastChatMessage(
    'system', 'Server', 0, 'Your vehicle was stored.', source, nil, 'system'
)
```

### `SendActionMessage`

Use this for pink, proximity-based roleplay actions from another system:

```lua
exports['cm-chat']:SendActionMessage(source, 'puts something in the trunk')
exports['cm-chat']:SendActionMessage(source, 'takes something from the trunk', 25.0)
```

The optional third argument overrides the radius. The export returns `true` if
the message was accepted.

### Admin action APIs

Register a reusable action template:

```lua
exports['cm-chat']:RegisterAdminActionMessage(
    'warn',
    'Administrator {admin}[{adminId}] warned {target}[{targetId}]. Reason: {reason}'
)
```

Broadcast it directly:

```lua
exports['cm-chat']:AdminActionBroadcast(source, 'warn', {
    targetName = 'First Last',
    targetCharacterId = 42,
    reason = 'Example reason'
})
```

Supported placeholders are `{admin}`, `{adminId}`, `{target}`, `{targetId}`,
and `{reason}`. CM Chat also listens for `cm-admin:server:actionLogged` and
automatically formats the built-in `kick`, `ban`, `freeze`, `unfreeze`, and
`silence` actions.

### Useful client events

From trusted server-side code:

```lua
TriggerClientEvent('cm-chat:client:open', targetSource)
TriggerClientEvent('cm-chat:client:clear', targetSource)
```

`cm-chat:client:addMessage` is the low-level render event. Prefer the server
exports above so routing, formatting, and validation stay consistent.

## Admin permissions and announcements

The `ADMIN` tab and `/a`/`/staff` commands accept any of the following:

- ACE permission `cm.admin`;
- ACE permission `command.admin`;
- `cm-admin:IsAdminActive(source)` returning `true`;
- `cm-admin:IsAdmin(source)` returning `true`.

The current `cm-admin` resource does not expose `IsAdminActive` or `IsAdmin`, so
configure one of the two ACE permissions unless those exports are added later.

Announcements use the separate `cm-admin:HasPermission` checks:

- `/announce`: `chat.announce`
- `/anon`: `chat.announce_anon`

When `cm-admin` is available, grant those permissions through its rank system.
When that export is unavailable, the current ACE fallback names are exactly:

```cfg
add_ace group.admin cm.chat.chat.announce allow
add_ace group.superadmin cm.chat.chat.announce_anon allow
```

The duplicated `chat` segment is intentional documentation of the current
implementation in `server/main.lua`; changing it requires a code change too.
The server console may always use `/announce` or `/anon`.

## Database logging

With `Config.EnableDatabaseLogs = true`, CM Chat creates `cm_chat_logs` on
startup and records player-sent chat messages. Each row contains:

- server source ID;
- character ID and resolved character name;
- channel and message;
- JSON metadata containing player identifiers and target/group information;
- creation time.

`oxmysql` must be started for this to work. If it is unavailable, chat delivery
continues but table creation, logging, and database name lookup are skipped.
Messages created through broadcast/action exports and admin announcements do
not pass through the player-message logger. Rows are retained until an operator
archives or deletes them, so set an access and retention policy appropriate for
the server.

To disable storage:

```lua
Config.EnableDatabaseLogs = false
```

## Security notes

- Use the integration exports from server-side code. Do not trust group IDs,
  character IDs, or permission claims sent by a client.
- Group values in CM Chat are message-routing metadata, not an authorization
  system. The resource that owns a family, organisation, job, or club must
  enforce its own permissions for sensitive actions.
- The compatibility events `cm-chat:server:setChatGroup` and
  `cm-chat:server:setChatGroups` accept values from the calling player. Do not
  use them as proof of membership; prefer the server exports.
- Compatibility character-resolution and character-loaded network events can
  also receive client-provided identity hints. Use `SetPlayerCharacter` from
  trusted server code and never treat a displayed chat identity as proof of
  authorization.
- The server strips line breaks, collapses whitespace, applies the cooldown,
  checks the blocked-word list, and limits message length. The NUI also escapes
  HTML before rendering.
- Directly triggering the low-level client render event bypasses server logging
  and routing checks.

## Troubleshooting

### Pressing `T` does nothing

- Confirm `cm-chat` is started.
- Confirm the player's `isLoggedIn` state is `true` or a supported character
  loaded event has fired.
- Close any other NUI that currently owns focus.
- Check whether the player changed the `cmchat` key mapping in FiveM settings.

### `Character is not loaded yet`

- Verify the character table and column names in `config.lua`.
- Confirm `oxmysql` is started if CM Chat must look up the name.
- For a custom framework, call `SetPlayerCharacter` with both ID and name.
- Character IDs are converted to numbers for display. A non-numeric ID works
  for lookup and logging but currently appears as `(0)` in the chat UI.

### A group tab is missing

- Confirm the player has a non-empty group value.
- Prefer `SetPlayerChatGroup`, which refreshes tabs immediately.
- If using state bags, reopen chat to request the latest channel list.
- Ensure both sender and recipient use the exact same cleaned group value.

### Admin chat or announcements are denied

- Admin chat and announcements use different checks. Review
  [Admin permissions and announcements](#admin-permissions-and-announcements).
- If `cm-admin:HasPermission` exists and returns `false`, its result is used;
  configure the permission in `cm-admin` rather than relying on ACE fallback.

### Chat messages are not logged

- Confirm `Config.EnableDatabaseLogs = true`.
- Confirm `oxmysql` starts before `cm-chat`.
- Check that the database account can create and insert into `cm_chat_logs`.

### Two chat interfaces appear

Stop the other chat resource and keep only one NUI chat implementation active.
