# Inventory UI Fullscreen Glass Update

Applied UI-only upgrade.

## Changed

- Reworked inventory UI into a full-screen glassmorphism/waterdrop style.
- Kept backpack as a 6 x 5 grid.
- Enlarged and rounded item slots with blur, reflection, and iPhone-style glass panels.
- Removed top bar buttons for weapon camouflage and creating items.
- Removed the Prime Account badge from the equipment side.
- Simplified hover tooltip so it only shows required quick details:
  - quantity
  - weight
  - durability when available
  - bag level/slots for bags
  - clothing type/style for clothing
  - category for normal items
- Right-click context menu still works for item actions.

## Files touched

- `ui/index.html`
- `ui/style.css`
- `ui/app.js`
