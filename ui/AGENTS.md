# CM FiveM UI Rules

These rules apply to every FiveM player-facing interface in this project,
including NUI pages, HUDs, inventories, banks, garages, houses, shops,
organisation and law/EMS/admin panels, modals, notifications, buttons,
prompts, and dashboards. They supplement the repository-root `AGENTS.md`;
the root instructions remain authoritative wherever both apply.

## Design standard

Build interfaces that feel modern, professional, and gaming-inspired while
staying clear, readable, and quick to use. Use any supplied reference
screenshots as a guide to typography, spacing, alignment, card structure,
button size, hierarchy, and usability. Do not copy their branding or exact
assets. Keep layouts uncluttered and readable at 1366 × 768 and ultrawide
resolutions.

Use the CM cyan and deep-teal identity. Do not add purple, pink, lime, or
unrelated neon accents. Use dark teal panels rather than plain black slabs;
avoid excessive borders, gradients, animation, empty space, and card walls.
Use approximately 8px corner radii for panels and cards.

## Required colour tokens

These exact values are the UI palette. Do not substitute approximations:

```css
--cm-bg: #0B171E;
--cm-bg-deep: #10222B;
--cm-panel: rgba(18, 36, 47, 0.94);
--cm-panel-solid: #142733;
--cm-border: #213B4A;

--cm-cyan: #00E5FF;
--cm-yellow: #FFC700;
--cm-green: #2ECC71;
--cm-orange: #FF8C00;
--cm-red: #E74C3C;

--cm-text: #FFFFFF;
--cm-text-secondary: #C2D2DC;
--cm-text-muted: #829DAE;
```

Colour meanings:

- `#00E5FF` (cyan) — primary theme, active states, focus, interaction
  prompts, informational states, and glow accents.
- `#FFC700` (yellow) — primary actions, normal confirmation buttons, active
  navigation indicators, and rank 1.
- `#2ECC71` (green) — cash, rewards, success, and completed states.
- `#FF8C00` (orange) — warnings, attention, secondary accents, and rank 2.
- `#E74C3C` (red) — errors, danger, critical alerts, hot status, and
  destructive actions.

`cm-ui` is the shared owner of UI primitives and tokens. Use its components,
fonts, and helpers instead of copying them into each resource. Its current
theme defines some overlapping variables with different values. When a UI
uses `cm-ui`, load the shared styles first, then apply the exact palette above
in the resource's stylesheet and map any legacy component aliases it uses to
these semantic tokens. Do not silently inherit conflicting defaults or
change the shared theme as an unrelated part of a feature task.

## Typography and spacing

Use a readable font such as the self-hosted DM Sans or Poppins from `cm-ui`,
Inter, Montserrat, or Segoe UI Variable. Keep text at or above these sizes:

| Use | Size |
| --- | --- |
| Main title | 28–34px |
| Section title | 18–22px |
| Card title | 14–17px |
| Body text | 13–15px |
| Labels | 10–12px |
| Important value | 20–32px |
| Buttons | 12–14px |

Use an 8px spacing scale: 4px for a tight icon gap, 8px for a compact gap,
12px for a normal gap, 16px for card padding, 24px between sections, and 32px
for major spacing.

## Shared components and confirmation

Use `cm-ui` shared components and design tokens wherever the integration
exists. Extend the shared component when a common capability is missing;
avoid resource-specific copies of shared UI behaviour. A confirmation helper
may be reused only when it meets the requirements below.

Every destructive, irreversible, costly, or world-changing action requires a
confirmation step before it is submitted. This includes cancelling parking;
removing a vehicle from the world; selling vehicles, houses, garages, or
items; deleting weapons, outfits, families, organisations, members, or saved
data; resetting settings or progress; transferring money or valuable items;
confirming purchases or fees; replacing models, images, routes, or saved
configurations; and removing ranks, permissions, or players. Never execute
these actions directly from one click.

Use or extend a reusable component with these class names:

```text
.cm-confirm-modal
.cm-confirm-modal__title
.cm-confirm-modal__message
.cm-confirm-modal__consequence
.cm-confirm-modal__actions
.cm-confirm-modal__confirm
.cm-confirm-modal__cancel
```

Each confirmation must have a clear uppercase title (for example,
`CONFIRM ACTION`), a precise description, the affected object's name, the
consequence or warning, and `CONFIRM` and `CANCEL` buttons. Destructive
actions must focus Cancel by default. Escape cancels; clicking outside cancels
when safe. Disable Confirm while processing and show loading, success, and
error states. Restore NUI focus and cursor state on every exit path. Use
yellow for normal confirmation, green for success, red for destructive
confirmation, and a dark teal secondary style for Cancel. Never use only vague
copy such as “Are you sure?”.

The modal is a presentation step only. The server must independently validate
the operation, permissions, ownership, price, and current state as
applicable. Never trust a client confirmation value as authorization.

## FiveM NUI behaviour

- Preserve existing Lua, NUI, callback, event, export, and gameplay behaviour
  during UI-only work. Do not change gameplay logic as a visual side effect.
- Treat NUI messages and client requests as untrusted; validate authoritative
  state and permissions on the server.
- Prevent duplicate opens and repeated submissions. Disable controls while a
  request is in flight and provide a force-close/reset path.
- Every world E-to-interact prompt in every resource must use the shared
  `cm-ui` prompt. Do not build a resource-specific E prompt in HTML, CSS, or
  another UI layer. The resource still owns its proximity checks and gameplay
  action; `cm-ui` owns the prompt presentation.
- Use `exports['cm-ui']:ShowInteract({...})` to show the prompt and
  `exports['cm-ui']:HideInteract()` to hide it when interaction is unavailable
  or related NUI opens. Keep it hidden until that interface has fully closed
  and the interaction is available again. Example:

  ```lua
  exports['cm-ui']:ShowInteract({
      key = 'E',
      label = 'OPEN GARAGE',
      name = 'Garage', -- optional
      role = 'PROPERTY', -- optional
  })
  ```

- Use the same shared `cm-ui` prompt for NPC interactions. When an NPC
  interaction needs a conversation or choice dialogue, use
  `exports['cm-ui']:OpenNpcDialogue(ped, options)` and its response/close
  exports. Do not create a separate NPC prompt or dialogue component in the
  consuming resource. Route selected actions through that resource's existing
  namespaced events and keep gameplay and authorization checks in their
  owning resource/server.
- Keep shared prompts centred or appropriately positioned, readable, and
  cyan. Use simple labels such as `[E] OPEN GARAGE`, `[E] ENTER HOUSE`,
  `[E] USE ATM`, or `[E] TAKE VEHICLE`.
- If a resource calls `cm-ui` exports, ensure `cm-ui` starts before the
  consumer and declare the dependency as required by its manifest setup.
- Escape returns to the previous submenu when one is open and closes the main
  interface otherwise.
- On every close, error, cancellation, and force-close path, release NUI focus
  and cursor state and restore any camera, HUD, control, or freeze state that
  this interface changed. Do not reset unrelated state owned by another
  system.
- Do not use CSS `backdrop-filter` or blur effects. Use solid or
  semi-transparent panels instead.
- Keep motion restrained and avoid noisy debug notifications for normal
  players. Put diagnostic detail in controlled logs or development/admin
  views.

## UI change workflow

Before changing an interface, inspect its resource and existing NUI flow, and
check for shared `cm-ui` components or established local patterns. Preserve
unrelated working-tree changes. Keep UI-only changes scoped to presentation
and input handling; follow the root `AGENTS.md` for cross-resource contracts,
server authority, validation, runtime restarts, and required reporting.
