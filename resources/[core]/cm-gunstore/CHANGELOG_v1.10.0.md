# cm-gunstore v1.10.0 — Manage NPCs from the UI + cinematic dialog

## Add gun store clerks without touching Lua
`/gunadmin` now has a **Manage NPCs** tab (admin-only, hidden for players):
- Walk anywhere in the world, fill in a Name (and optionally a shop label,
  ped model, and scenario), then click **Add NPC Here**. The clerk spawns at
  your exact position/heading immediately for every player on the server —
  no resource restart, no editing `shared/config.lua`.
- Each NPC is a fully working gun store: it opens the normal dialog, sells
  from the same catalog, and honors the same purchase-distance check as the
  built-in shops.
- NPCs are stored in a new `cm_gunstore_npcs` database table, so they survive
  a server restart. Remove one any time with the Remove button in the list.
- Config.Shops in `shared/config.lua` is untouched and still works exactly as
  before — the two lists are merged client + server side.

## NPC dialog now uses cm-ui (same component every other job NPC uses)
Talking to a clerk (walk up, press E) no longer uses a one-off dialog card
built into this resource. It now calls the shared `cm-ui` design system --
the same `ShowInteract` / `OpenNpcDialogue` components cm-license,
cm-electrician, and cm-police already use for their NPCs (see
`cm-ui/docs/CM_UI_USAGE.md`). That gets the gun store clerk the same
scripted-camera cinematic conversation, letterbox NUI, and "I'm not
interested right now" / Esc dismissal for free, with zero camera/NUI code
of its own to maintain.

This resource no longer ships its own "Press E" prompt or dialog-card HTML/
CSS/JS -- that DOM was removed from `web/index.html`/`app.js`/`style.css`.
`cm-ui` is a soft dependency (like ox_target): if it isn't running, the
clerk's prompt/dialogue simply won't show (console warning), same as
cm-electrician/cm-license behave without it. Put `ensure cm-ui` before
`ensure cm-gunstore` in `server.cfg`.

Dialog copy is still yours to edit in `shared/config.lua`:
`Config.Ped.dialog.title` / `optionStore` / `optionLicense` / `optionClose`.

## New server events (internal)
- `cm-gunstore:server:requestShops` — client asks for the current custom NPC
  list on resource start.
- `cm-gunstore:server:adminRequestNpcs` / `adminCreateNpc` / `adminDeleteNpc`
  — all gated behind the existing `isAdmin` ace check.
- `cm-gunstore:client:npcsSync` (broadcast to `-1`) — pushes the merged
  custom-NPC list to every client immediately after an admin adds/removes one.
- `cm-gunstore:client:licenseResult` — server's answer to a license purchase
  made from inside the cm-ui dialogue, shown inline via `NpcDialogueRespond`.

## To apply after updating
1. Make sure `cm-ui` is started before `cm-gunstore` in `server.cfg`.
2. Restart cm-gunstore. The `cm_gunstore_npcs` table is created automatically
   on first start (same pattern as `cm_gun_catalog`).
3. Open `/gunadmin`, go to the **NPCs** tab, and add your first custom clerk.
