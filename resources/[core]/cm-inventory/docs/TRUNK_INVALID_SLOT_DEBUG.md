# Trunk Invalid Slot Debug Build

This build turns on verbose debug in both `cm-inventory` and `cm-vehicles`.

## How to test

1. Restart both resources:

```txt
restart cm-inventory
restart cm-vehicles
```

2. Open the vehicle trunk, stand near the trunk, then press `I`.
3. Drag an item from player inventory to one of the first usable trunk slots.
4. Check:
   - **F8 client console** for `[CM-INVENTORY-CLIENT]` lines.
   - **Server console** for `[CM-INVENTORY]`, `[CM-INVENTORY][UI-DEBUG]`, and `[CM-VEHICLES]` lines.

## Important lines to send back

Send the lines that contain:

```txt
[CM-VEHICLES] Opening cm-inventory external trunk
[CM-INVENTORY] OPEN EXTERNAL
[CM-INVENTORY-CLIENT] moveItem callback
[CM-INVENTORY] MOVE RAW
[CM-INVENTORY] MOVE NORMALIZED
[CM-INVENTORY] moveItem failed
```

Those lines will show whether the bug is:

- UI is sending the wrong `toSlot`.
- Server has no external trunk context open.
- Slot prefix is wrong.
- Storage slot number is outside allowed slot count.
- Source player slot is invalid.

## Toggle debug

Debug is ON by default in this build. You can toggle it in F8:

```txt
/invdebug
```
