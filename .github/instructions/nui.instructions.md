---
applyTo: "**/{html,ui}/**/*,**/*.js,**/*.css,**/*.html"
---

# FiveM NUI

- Use the existing CM dark, cyan/ice-blue visual language and `cm-ui` primitives where available.
- Keep interfaces readable, compact, responsive, and local-asset based. Do not use purple as the primary accent, `backdrop-filter`, giant glowing gradients, generic card walls, or unnecessary horizontal scrolling.
- Null-check optional DOM elements and validate NUI payloads.
- Avoid per-frame DOM rebuilding and oversized repeated payloads.
- Preserve callback compatibility; close/ESC must restore focus.
- Run `node --check` after JavaScript changes.
