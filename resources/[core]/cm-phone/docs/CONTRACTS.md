# cm-phone contracts

## Server exports

| Export | Access | Returns |
|---|---|---|
| `GetPhoneNumber(characterId)` | any resource | `'AAA-BBBB'` or `nil` |
| `GetPhoneNumberForSource(source)` | any resource | number of the source's loaded character, or `nil` |
| `IsNumberBlocked(ownerCharacterId, number)` | any resource | boolean |
| `GetCharacterByPhoneNumber(number)` | `Config.TrustedResources` only | character ID or `nil` (identity bridge) |
| `SendSystemMessage(characterId, title, body, payload?)` | `Config.TrustedResources` only | `ok, {conversationId,id}` or `false, reason`. Receive-only thread titled `title`; offline characters get it on next load |
| `CreateNotification(characterId, { title, message })` | `Config.TrustedResources` only | boolean; transient toast, not persisted |

| `RegisterPhoneService(serviceId, { create, status, cancel?, availability? })` | resources in `Config.Services.Sources` for that id | `true` or `false, reason`. Service Marketplace adapter registration; see `docs/SERVICES.md` |
| `UnregisterPhoneService()` | registering resource | `true` |
| `PushPhoneServiceStatus(characterId, serviceId, status)` | the registered owner of that service | `true` / `false, reason`. Event-driven status toast, public shape only |
| `TranslateContractStatus(status, completionMode)` | any resource | player-facing state key for `cm-contracts` statuses |

Not exported by design: sending as a character, reading messages/contacts, listing numbers.

## Server events (local, non-networked)

| Event | Payload | Use |
|---|---|---|
| `cm-phone:server:serviceRegistryReady` | none | fired after start; service owners re-register their adapter |

| Event | Payload | Use |
|---|---|---|
| `cm-phone:server:callStateChanged` | `callId, state, callerSource, calleeSource` (`dialing|ringing|active|ended`) | hook for a future voice bridge. cm-phone performs **no** audio routing |

Internal (`cm-phone:internal:*`) events are implementation details and not contracts.

## Client events (server → client; targeted, never broadcast)

`cm-phone:client:serviceStatus` (owner status push), `cm-phone:client:identity`, `cm-phone:client:message` (preview only, no body for closed phone), `cm-phone:client:call`, `cm-phone:client:notify`.
There are no client → server net events; all requests use ox_lib callbacks below.

## ox_lib callbacks (client → server, all prefixed `cm-phone:`)

Every callback returns `{ ok = true, data = ... }` or `{ ok = false, error = code, extra? }`.
Context (character + number) and rate limits are applied before the handler runs.

`bootstrap`, `conversations`, `openConversation{conversationId,before?}`, `markRead(conversationId)`, `send{conversationId|number,text}`,
`sendLocation{conversationId|number,label?}`, `contactSave{id?,number,name,favourite?}`, `contactDelete(id)`, `block(number)`, `unblock(number)`,
`groupCreate{name,numbers[]}`, `groupAdd{conversationId,number}`, `groupRemove{conversationId,number}`, `groupLeave(conversationId)`,
`services`, `serviceStatus(serviceId)`, `serviceRequest{serviceId,fields}`, `serviceCancel{serviceId,ref}` (Service Marketplace; the phone stores no requests), `dial(number)`, `answer`, `decline`, `hangup`, `calls`, `adverts`, `advertPost(text)`, `emergency{service='police'|'ems',details?}`.

NUI → Lua uses a single whitelisted `api` NUI callback (`client/main.lua` `ENDPOINTS`) plus `close` and `setGps`.

Error codes: `rate_limited, busy, invalid_request, invalid_number, invalid_name, invalid_recipient, invalid_message, invalid_target,
duplicate_number, contact_limit, not_found, forbidden, undeliverable, unavailable, already_in_call, no_call, already_active, location_unavailable,
group_limit, already_member, insufficient_funds, cooldown, dispatch_failed, character_not_loaded, no_phone, internal_error,
service_unavailable, invalid_service, invalid_field, missing_field, already_active, service_failed, status_unavailable, cancel_not_allowed, not_found, no_waypoint`.

## Consumed contracts

- `cm-playerdata`: `GetCharacterId`, `IsDead`, `RemoveCash/RemoveBank/AddCash/AddBank` (advert fee and refund), events `cm-playerdata:server:characterLoaded|characterUnloaded`.
- `cm-ems:CreateAmbulanceCall(source, {details, emergencyType='phone', priority=2})`, `cm-law:CreateLawCall(source, details)`.
- `cm-hud:client:notify` (optional), `cm-admin:server:addLog` (category `phone`, no message text).
- `characters` table (read-only join to confirm a number still belongs to an existing character).

## Permissions

None added. High-trust exports use the `Config.TrustedResources` allowlist.

## Integration notes for other resources

- `cm-hub/server/main.lua` reads `characters.phone_number`, which does not exist in this database. It should call `exports['cm-phone']:GetPhoneNumber(charId)`
  (SHARED INTEGRATION REQUIRED, owner `cm-hub`; not changed here).
- Future business/taxi/mechanic requests should use `SendSystemMessage` / `CreateNotification` after being added to `Config.TrustedResources`.
- Taxi / mechanic / courier requests go through the Service Marketplace adapter (`docs/SERVICES.md`); `cm-taxi` needs a small owner-side change (SHARED INTEGRATION REQUIRED — cm-taxi).
