# cm-ui

Central UI theme and reusable components for CM Framework / Grand RP.

Start this before UI-heavy resources:

```cfg
ensure cm-ui
ensure cm-core
ensure cm-auth
ensure cm-playerdata
ensure cm-characters
ensure cm-spawn
ensure cm-hud
ensure cm-admin
```

Use in NUI:

```html
<link rel="stylesheet" href="nui://cm-ui/web/cm-theme.css">
<link rel="stylesheet" href="nui://cm-ui/web/cm-components.css">
<link rel="stylesheet" href="nui://cm-ui/web/cm-icons.css">
<script src="nui://cm-ui/web/cm-ui.js"></script>
```

For the reusable tactical / operations presentation layer, load the opt-in
style sheet after the shared components:

```html
<link rel="stylesheet" href="nui://cm-ui/web/cm-style.css">
```

It provides `.cm-style-card`, `.cm-style-slot`, `.cm-style-badge`,
`.cm-style-btn`, `.cm-style-row`, `.cm-style-progress`, modal, toast, and
event-card primitives. It is presentation-only; the owning resource remains
responsible for NUI callbacks, permissions, prices, ownership, and server-side
validation.
