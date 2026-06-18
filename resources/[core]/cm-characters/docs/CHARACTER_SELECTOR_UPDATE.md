# cm-characters v1.1 Selector + Simplified Creator Update

## What changed

- Character selector UI now matches the dark CM/auth style.
- Selector shows existing characters as cards.
- If the account has 2 characters, both character cards are shown.
- If the account has 1 character, that character is shown plus a create-card for the empty slot.
- Selecting a character card does not instantly spawn. It now:
  - focuses the preview ped,
  - shows details,
  - enables the **Enter City** button.
- Details panel shows:
  - cash,
  - bank,
  - level,
  - rank,
  - gender,
  - playtime,
  - created date,
  - permanent character ID.
- The client spawns preview peds for the available characters while the selector is open.
- Background music was added to character UI with mute toggle.
- Appearance/customization is simplified:
  - makeup category removed,
  - ageing/blemishes/complexion/sun/moles removed,
  - chest hair removed,
  - simple body/face/hair/starter-clothes setup only.

## Important files changed

```text
client/main.lua
client/creator.lua
client/appearance.lua
server/slots.lua
ui/index.html
ui/style.css
ui/app.js
ui/appearance/app.js
ui/appearance/style.css
fxmanifest.lua
```

## Selector flow

```text
cm-auth login success
↓
cm-auth triggers cm-characters:client:openSelector
↓
cm-characters asks server for character slots
↓
server returns slot data + character stats + appearance preview data
↓
client spawns 1 or 2 preview peds
↓
UI displays character cards
↓
player clicks a character card
↓
details panel updates
↓
player clicks Enter City
↓
cm-characters:server:selectCharacter fires
↓
cm-core:characterLoaded triggers spawn/playerdata systems
```

## Music

Music file:

```text
ui/audio/character-theme.wav
```

Mute state is saved in NUI localStorage:

```text
cm_char_music_muted
```

## Notes

Preview peds use the saved base appearance from `characters.appearance_json`. Since clothing is handled by inventory equipment in your system, the preview may not always show every equipped clothing item unless you later add an inventory-preview bridge.


## v1.1.1 UI Ready Fix

Fixed the case where the music plays but the selector is invisible. The NUI now sends `uiReady` after `app.js` mounts, and the Lua client replays `showApp`/`showSlots` messages for a few seconds after auth opens the selector. Added `/chartestui` for quick client-side testing after login.

### Why music could play while UI stayed invisible
The audio tag loads with the NUI page, but if Lua sends `showApp` before `ui/app.js` finishes mounting, the message can be missed. This version adds a `uiReady` callback and replay loop so the selector becomes visible after the page is ready.

Also removed optional chaining from the selector/appearance JavaScript for better FiveM CEF compatibility.
