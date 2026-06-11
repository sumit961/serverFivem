# cm-inventory v3.8 player polish

Adds player-inventory-only improvements:

- Metadata details in tooltip/right-click panel
- Durability display and persistence
- Weapon durability decreases when shooting
- Armor durability syncs with equipped body armor value
- Hotbar quick use for slots 1-5
- Amount selectors for divide, give and drop
- Use progress + item cooldowns
- Rarity/type glow rules:
  - normal: no glow
  - unique: blue line/glow
  - rare: red line/glow
- Bag level slot and capacity system:
  - no bag: no backpack slots, 25kg
  - level 1 bag: 6 backpack slots, 45kg
  - level 2 bag: 8 backpack slots, 55kg
  - level 3 bag: all 30 backpack slots, 82kg
  - level 4 bag: all 30 backpack slots, 100kg

Test commands:

```text
testgive water 5
testgive bag_level1 1
testgive bag_level2 1
testgive bag_level3 1
testgive bag_level4 1
testgive weapon_pistol 1
testgive ammo_9mm 30
testgive armor 1
inv
```

Use bag item to equip it into the bag slot. Locked backpack slots are visible but blocked.
