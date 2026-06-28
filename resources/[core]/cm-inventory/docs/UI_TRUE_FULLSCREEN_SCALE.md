# UI True Fullscreen Scale Fix

Applied final CSS overrides so the inventory behaves like a full-screen NUI:

- The CEF-safe glass background now fills 100vw / 100vh.
- Topbar spans the screen instead of acting like a small panel.
- Inventory slots scale up using viewport width and height.
- Backpack/equipment spacing is tightened.
- Bottom hint is fixed to the bottom of the screen.
- No backdrop-filter is used on fullscreen elements to avoid FiveM black-rectangle rendering bugs.
