# CM Inventory v3.9 Bag Lock Fix

Install:
1. Rename `cm-inventory-v3.9-baglockfix` to `cm-inventory`.
2. Rename `cm-itemactions-v2.6-baglockfix` to `cm-itemactions`.
3. Put both in `resources/[core]/`.
4. Restart `cm-inventory` and `cm-itemactions`.

Test:
```text
testgive bag_level1 1
testgive water 5
inv
```
Equip bag level 1, put water in backpack slots, then try to remove/downgrade the bag. The action should be blocked until the affected backpack slots are empty.
