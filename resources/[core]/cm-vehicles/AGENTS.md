# cm-vehicles — Agent Instructions

## CRITICAL EXCLUSION: VEHICLE G-MENU IS APPROVED & FROZEN

The existing Vehicle G-menu is **APPROVED** and must remain visually and functionally unchanged.

Primary protected implementation:
- `client/menu.lua`
- `ui/index.html`
- `ui/style.css`
- `ui/app.js`
- and any interactions specifically responsible for the current Vehicle G-menu presentation.

### STRICT RULES:
DO NOT:
- Redesign the Vehicle G-menu
- Change its layout, dimensions, or positioning
- Change its typography or fonts
- Change its icons
- Change its color palette or theme variables
- Change button or action placement
- Change interaction prompt appearance
- Change vehicle targeting behavior
- Change G-key behavior
- Change animation or transitions
- Replace it with a generic CM dashboard or menu
- Force `.cm-btn`, `.cm-card`, `.cm-tabs`, etc. onto it
- Change player-vs-vehicle G-menu interaction arbitration (`cmVehicleInteractDist` / `cmPlayerInteractDist`)
- Change its distance or target selection behavior

The Vehicle G-menu is intentionally exempt from server-wide CM UI visual migration.

### ALLOWED CHANGES:
Only modify Vehicle G-menu code if absolutely required for:
1. A confirmed gameplay bug
2. Security fix
3. Compatibility break
4. Explicit future request from the user

### SCOPE DISTINCTION:
This protection applies strictly to the **Vehicle G-menu / vehicle interaction menu**.
It does **NOT** prevent migration of:
- Law G-menu
- EMS G-menu
- Family G-menu
- House UI
- Garage management UI
- Parking management UI
- Vehicle Shop UI
- Inventory UI

### REGRESSION VERIFICATION:
After every UI migration or dependency change:
1. Walk near a vehicle.
2. Open the Vehicle G-menu (G key).
3. Verify its appearance is unchanged.
4. Verify all existing options remain in the same layout.
5. Verify G interaction prompt appears correctly.
6. Verify player/vehicle interaction arbitration still prevents duplicate G prompts.
7. Verify ESC/close behavior.
8. Verify vehicle actions still function.
If any visual difference is observed in the Vehicle G-menu caused by a migration: **REVERT THAT CHANGE IMMEDIATELY**.
