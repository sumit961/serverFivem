# cm-admin v2.7.0 — launcher-only Developer panel

- Developer entries can only open a resource-owned panel.
- Removed command execution, arbitrary client actions and form submissions
  from the Developer page.
- Launcher clicks remain permission-gated and are written to the developer
  audit category.
- House, climate/time, HUD, clothing, weapon and vehicle-catalog panels now
  self-register their Open buttons.
- Each privileged target resource re-checks its own authorization before
  opening; actions remain inside that resource's existing secured callbacks.
- Existing standalone commands remain available for backward compatibility,
  but cm-admin no longer invokes them.
