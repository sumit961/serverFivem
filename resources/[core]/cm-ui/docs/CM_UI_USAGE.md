# CM UI Usage

`cm-ui` is the central design system for the CM Framework / Grand RP server.

It owns only shared UI style and helper functions.

It does not own gameplay logic, money, admin permissions, player data, inventory, vehicles, weather, or jobs.

## Add to any NUI HTML

```html
<link rel="stylesheet" href="nui://cm-ui/web/cm-theme.css">
<link rel="stylesheet" href="nui://cm-ui/web/cm-components.css">
<link rel="stylesheet" href="nui://cm-ui/web/cm-icons.css">
<script src="nui://cm-ui/web/cm-ui.js"></script>
```

### CM Style language

Resources that need the denser operations / parking presentation can opt in:

```html
<link rel="stylesheet" href="nui://cm-ui/web/cm-style.css">
```

The style language exposes reusable `.cm-style-*` primitives for slot grids,
status badges, metric rows, progress bars, inputs, buttons, confirmation
modals, toasts, and event cards. Load it after `cm-theme.css` and
`cm-components.css`. It uses the exact CM cyan / deep-teal palette and does
not use external fonts, icons, blur, or `backdrop-filter`. Component controls
use fixed pixel sizing for consistent readability across resolutions; only the
grid layout reflows on smaller screens.

## Basic layout

```html
<div class="cm-app">
  <div class="cm-window">
    <div class="cm-window-header">
      <div>
        <div class="cm-window-title">Admin Panel</div>
        <div class="cm-window-subtitle">CM Framework</div>
      </div>
      <button class="cm-btn cm-btn-secondary">Close</button>
    </div>
    <div class="cm-window-body cm-scrollbar">
      <button class="cm-btn">Save</button>
      <button class="cm-btn cm-btn-danger">Delete</button>
    </div>
  </div>
</div>
```

## JS helpers

```js
CMUI.toast('Saved successfully', 'success');

const ok = await CMUI.confirm({
  title: 'Delete item',
  message: 'Are you sure?',
  confirmText: 'Delete',
  danger: true
});

CMUI.postNui('close', {});
```

## Theme rule

Never use CSS `backdrop-filter` in FiveM NUI.

Use central variables from `cm-theme.css` instead.

## Interact prompt (any resource)

`cm-ui` owns a persistent NUI overlay (`web/index.html`, declared as `ui_page`
in its manifest), so any other resource can trigger the shared components
below via `exports['cm-ui']` — no HTML/CSS to copy, no NUI focus juggling.

The "Press [key]" interaction prompt (originally cm-police's E-to-interact
label):

```lua
exports['cm-ui']:ShowInteract({
    key = 'E',
    label = 'INTERACTION',
    name = 'Officer Reyes',   -- optional
    role = 'CM POLICE',       -- optional
})

exports['cm-ui']:HideInteract()
```

Passive — draws no NUI focus, safe to call every frame from a proximity loop.

## Cinematic NPC dialogue (any resource)

The scripted-camera NPC dialogue (originally cm-police's
`client/npc_dialogue.lua` + the camera work in `client/cinematics.lua`), now
generalized in `client/dialogue.lua`:

```lua
exports['cm-ui']:OpenNpcDialogue(ped, {
    name = 'Officer Reyes',
    role = 'CM POLICE',
    quote = 'How can I help you today?',
    continueLabel = 'See services',
    deferChoices = true,                       -- show Continue first, reveal choices after
    serviceLabel = 'Please choose the service you need.',
    choices = {
        {
            id = 'report', label = 'File a report', description = 'Start an incident report',
            event = 'my-resource:client:dialogueChoice',   -- TriggerEvent'd on YOUR client
            payload = { kind = 'report' },
            close = false,                       -- keep the dialogue open (default true = close)
        },
    },
    -- No choices? Use continueEvent/continuePayload instead — fired when the
    -- player presses Continue on a plain single-line dialogue.
    continueEvent = 'my-resource:client:dialogueContinue',
    -- Fired only when the player dismisses via "I'm not interested right
    -- now" (not on a choice/continue path — those have their own events).
    -- Use it to restore whatever state you changed before opening (HUD, etc).
    closeEvent = 'my-resource:client:dialogueDismissed',
})
```

Guaranteed behavior, so you don't have to handle it per-resource:

- **Esc closes it.** Same as clicking "I'm not interested right now" — fires
  `closeEvent`, not any choice/continue event.
- **The interact prompt never shows while the dialogue is open.** `ShowInteract`
  is a no-op whenever `.cm-dialogue` is visible, and `OpenNpcDialogue` hides
  any prompt already on screen the instant it opens.
- **The player is never teleported.** Opening the dialogue only turns the
  player to face the ped (`SetEntityHeading`) from wherever they were already
  standing — it never repositions them. Pass `faceOff = false` to skip even
  the turn.

Choices fire an **event name**, not a Lua function — exported functions run
inside cm-ui's own environment and Lua closures don't marshal across
resources, so your own resource listens for the event it named:

```lua
AddEventHandler('my-resource:client:dialogueChoice', function(payload)
    -- do your work, then respond:
    exports['cm-ui']:NpcDialogueRespond('Report filed.', 'success', 2200)
end)
```

Other calls:

```lua
exports['cm-ui']:NpcDialogueRespond(message, tone, closeDelayMs)  -- tone: 'inform' | 'success' | 'error'
exports['cm-ui']:NpcDialogueRestoreChoices(promptText)            -- back to the choice list
exports['cm-ui']:CancelNpcDialogue()
exports['cm-ui']:IsNpcDialogueOpen()
```

## Previewing the UI

In-game: run `/cmuistyle` (or `/cmuipreview`) to open the reusable CM Style
showcase with tabs for slot grids, components, modals, event cards, and the
class contract. Press Escape or use `CLOSE PREVIEW` to exit. Run
`/cmuidialoguepreview` for the original demo ped and cinematic dialogue flow.

No FiveM needed: open `resources/[core]/cm-ui/web/preview.html` directly in a
browser (double-click it, or `start` it from a terminal) — it loads the same
CSS/JS and lets you trigger every component from on-screen buttons.
