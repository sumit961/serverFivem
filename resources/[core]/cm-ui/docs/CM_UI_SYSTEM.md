# CM UI Design System & Contract v2.0.1

Authoritative specification for all FiveM player-facing interfaces across the CM framework server.

---

## 1. Visual Identity & Authoritative Palette

All interfaces share the dark teal / cyan identity. Purple accents are strictly prohibited.

```css
--cm-bg: #0B171E;
--cm-bg-deep: #10222B;

--cm-panel: rgba(18, 36, 47, 0.94);
--cm-panel-solid: #142733;
--cm-panel-soft: rgba(20, 39, 51, 0.94);
--cm-panel-hover: rgba(25, 48, 62, 0.98);

--cm-border: #213B4A;
--cm-border-soft: rgba(33, 59, 74, 0.72);
--cm-border-focus: #00E5FF;
--cm-border-danger: rgba(231, 76, 60, 0.55);

--cm-cyan: #00E5FF;       /* Active states, primary system accent, slot outlines */
--cm-blue: #1E88E5;       /* Secondary accents, deep focus */
--cm-yellow: #FFC700;     /* Important CTAs, primary purchase/actions, owned highlight */
--cm-green: #2ECC71;      /* Money, success, positive status, available */
--cm-orange: #FF8C00;     /* Warnings, caution, intermediate status */
--cm-red: #E74C3C;        /* Destructive actions, cancel, removal, error */

--cm-text: #FFFFFF;       /* Primary text */
--cm-text-secondary: #C2D2DC; /* Secondary body */
--cm-text-muted: #829DAE; /* Muted labels and timestamps */
```

---

## 2. Responsive Root Scale & Typography

DO NOT use raw `vw` (such as `3vw` or `2vw`) for standard text or buttons.
Use the responsive root scale defined on `html`:

```css
html {
    font-size: clamp(
        13px,
        min(0.833vw, 1.481vh),
        20px
    );
}
```

- 1920×1080: `1rem ≈ 16px`
- 1366×768: `1rem ≈ 13px`
- 2560×1440: `1rem ≈ 20px`
- 3840×2160 (4K): `1rem ≈ 20px` (clamped)

### Font Scale Tokens
- `--cm-text-xs`: `0.7rem`
- `--cm-text-sm`: `0.75rem`
- `--cm-text-md`: `0.875rem`
- `--cm-text-lg`: `1rem`
- `--cm-title-sm`: `1.125rem`
- `--cm-title-md`: `1.5rem`
- `--cm-title-lg`: `2rem`

Primary Font: `DM Sans` (self-hosted in `cm-ui/web/fonts/`)
Display Font: `Poppins` (self-hosted in `cm-ui/web/fonts/`)

---

## 3. Size & Spacing Tokens

- `--cm-radius-sm`: `0.375rem`
- `--cm-radius`: `0.5rem` (Authoritative panel/card/button radius)
- `--cm-radius-lg`: `0.75rem`
- `--cm-radius-pill`: `9999px`

Spacing rhythm:
- `--cm-space-1`: `0.25rem`
- `--cm-space-2`: `0.5rem`
- `--cm-space-3`: `0.75rem`
- `--cm-space-4`: `1rem`
- `--cm-space-5`: `1.5rem`
- `--cm-space-6`: `2rem`
- `--cm-space-8`: `3rem`

Safe Screen Area:
- `--cm-screen-pad-x`: `clamp(1rem, 2vw, 2.5rem)`
- `--cm-screen-pad-y`: `clamp(1rem, 2vh, 2rem)`

---

## 4. Standard Button Heights & Variants

Button heights must use `rem`:
- Small: `height: 2.5rem;` (`.cm-btn-sm`)
- Medium: `height: 3.25rem;` (`.cm-btn-md` / `.cm-btn`)
- Large: `height: 4rem;` (`.cm-btn-lg`)

Classes:
```html
<button class="cm-btn cm-btn-primary">PRIMARY CTA (YELLOW)</button>
<button class="cm-btn cm-btn-cyan">SYSTEM ACTION (CYAN)</button>
<button class="cm-btn cm-btn-secondary">CANCEL / DISMISS</button>
<button class="cm-btn cm-btn-danger">DESTRUCTIVE ACTION (RED)</button>
<button class="cm-btn cm-btn-success">CONFIRM PURCHASE (GREEN)</button>
```

---

## 5. Authoritative Confirmation Modal (v2.0.1)

Every NUI confirmation MUST use `await CMUI.confirm(...)`. Native `window.confirm()` is strictly forbidden.

### In-NUI JavaScript Confirmation:
```javascript
const confirmed = await CMUI.confirm({
    title: 'REMOVE VEHICLE?',
    message: 'This will remove the vehicle from your garage slot permanently.',
    confirmText: 'REMOVE',
    cancelText: 'CANCEL',
    danger: true,
    dismissOnBackdrop: true // Set to false for critical / high-risk operations
});

if (confirmed) {
    // perform action
}
```

### Confirmation Contract & Architecture:
1. **FIFO Queue Serialization**: Calling `CMUI.confirm()` while another confirmation is open serializes requests into a resilient FIFO queue. Never hangs, never orphans promises, never leaves ghost backdrops.
2. **Single-Settle Guarantee**: Every confirmation modal resolves its Promise exactly once (`true` or `false`) and immediately advances any queued confirmations.
3. **DOM-Only Context**: `CMUI.confirm` operates entirely within the host resource's DOM. It NEVER calls `SetNuiFocus` or touches parent focus state.
4. **Keyboard Safety**: Cancel button receives default keyboard focus immediately upon display.
5. **Escape Key Handling**: `Escape` is captured at window capture phase, preventing parent screen close handlers from firing prematurely, dismissing the confirmation, and resolving `false`. Parent screens remain open.
6. **Backdrop Click Dismissal**: Clicking directly on the `.cm-modal-backdrop` (outside `.cm-modal`) resolves `false` by default. Set `dismissOnBackdrop: false` for high-risk flows where explicit button clicks are required.
7. **Cancel / Confirm**: Clicking Cancel resolves `false`. Clicking Confirm resolves `true`.

### World / Lua Confirmation Bridge:
**SCOPE: WORLD-SCRIPT CONFIRMATION ONLY**
The Lua export `exports['cm-ui']:Confirm(...)` is strictly intended for gameplay scripts (such as world interaction prompts, G-menus, or job tasks) where NO parent NUI interface is currently open:

```lua
local confirmed = exports['cm-ui']:Confirm({
    title = 'CONFIRM ACTION',
    message = 'Are you sure you want to proceed?',
    confirmText = 'CONFIRM',
    cancelText = 'CANCEL',
    danger = true
})
```

- If another NUI interface is already open (e.g. House, Family, Bank): **DO NOT** call the Lua bridge. Use `await CMUI.confirm()` inside the in-page JavaScript.
- The Lua bridge safely tracks whether it acquired NUI focus and only releases focus upon completion if `cm-ui` acquired it.
- Fail-safe concurrency: does not stack multiple world confirmations.
- `onResourceStop` lifecycle safety: if `cm-ui` or the calling resource stops while awaiting, the promise resolves `false`, the modal is dismissed, and any acquired focus is cleanly released.

---

## 6. Authoritative Toast Notifications

Toasts are anchored at the bottom-left (`left: 1.5vw; bottom: 4vh;`).
Dimensions use `rem`.

```javascript
CMUI.toast('Vehicle successfully stored in garage.', 'success');
CMUI.toast('Transaction declined: insufficient funds.', 'error');
CMUI.toast('Maintenance scheduled in 5 minutes.', 'warning');
CMUI.toast('GPS route updated.', 'info');
```

---

## 7. Cards, Tabs, Inputs & Slots

### Cards
```html
<div class="cm-card cm-card-interactive">
    <h3>Property Slot #1</h3>
    <p>Status: Occupied</p>
</div>
```

### Tabs
```html
<nav class="cm-tabs">
    <button class="cm-tab cm-active" data-cm-tab="overview">OVERVIEW</button>
    <button class="cm-tab" data-cm-tab="members">MEMBERS</button>
</nav>
```

### Inputs
```html
<label class="cm-label">TRANSFER AMOUNT</label>
<input type="text" class="cm-input" placeholder="Enter amount...">
```

### Parking / Garage Slots
```html
<div class="cm-slot-grid">
    <div class="cm-slot cm-slot--available">...</div>
    <div class="cm-slot cm-slot--selected">...</div>
    <div class="cm-slot cm-slot--owned">...</div>
</div>
```

---

## 8. Exact Shared Load Order for New Resources

Every NUI resource must link stylesheets and scripts in this exact order:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CM Resource</title>
    <!-- 1. Central theme & reset -->
    <link rel="stylesheet" href="nui://cm-ui/web/cm-theme.css">
    <!-- 2. Reusable components (buttons, cards, modals, tabs, badges, slots) -->
    <link rel="stylesheet" href="nui://cm-ui/web/cm-components.css">
    <!-- 3. Layout shells, headers, grids, and action bars -->
    <link rel="stylesheet" href="nui://cm-ui/web/cm-layout.css">
    <!-- 4. Shared icon definitions -->
    <link rel="stylesheet" href="nui://cm-ui/web/cm-icons.css">
    <!-- 5. Resource local layout stylesheet -->
    <link rel="stylesheet" href="style.css">
</head>
<body>
    ...
    <!-- Shared CM UI Kernel JS -->
    <script src="nui://cm-ui/web/cm-ui.js"></script>
    <script src="app.js"></script>
</body>
</html>
```

---

## 9. Forbidden Patterns

1. **DO NOT redefine central selectors outside `cm-ui`:**
   `.cm-btn`, `.cm-modal`, `.cm-toast`, `.cm-card`, `.cm-input`, `.cm-tab`, `.cm-badge`, `.cm-slot`, `.cm-actions`, `.cm-screen` (including prefixed variants such as `body .cm-btn`, `button.cm-btn`, or `div.cm-card`).
2. **DO NOT override central CM tokens:**
   `--cm-primary`, `--cm-cyan`, `--cm-yellow`, `--cm-green`, `--cm-red`, `--cm-bg`, `--cm-panel`, `--cm-border`, `--cm-radius`, `--cm-font`.
3. **DO NOT use native `window.confirm()` or `confirm()` in FiveM NUI.**
4. **DO NOT use CSS `backdrop-filter`.**
5. **DO NOT use purple as a primary/secondary UI accent.**
6. **DO NOT re-declare `@font-face` for `Poppins` or `DM Sans` in resource stylesheets.**
7. **DO NOT use raw `vw/vh` on regular text sizes or standard button heights.**
8. **DO NOT apply custom `font-family` to standard `.cm-*` controls.**
9. **DO NOT load resource-local stylesheets before `cm-theme.css`.**
10. **DO NOT violate canonical asset load order (`cm-theme.css` -> `cm-components.css` -> `cm-layout.css` -> `cm-icons.css` -> local CSS -> `cm-ui.js`).**
