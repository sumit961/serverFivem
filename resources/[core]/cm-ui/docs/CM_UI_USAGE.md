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
