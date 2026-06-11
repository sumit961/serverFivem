# Bag lock fix

Changing, downgrading, removing, dropping, or giving the active bag is blocked unless every backpack slot that would become locked is empty after the action.

Examples:
- Bag level 3 -> Bag level 1: slots backpack-7 to backpack-30 must be empty.
- Bag level 1 -> No bag: backpack-1 to backpack-30 must be empty.
- Bag level 1 -> Bag level 2: allowed, because it unlocks more slots.
- Removing active bag: blocked if any backpack slot contains items.

The check also blocks downgrade/removal if current inventory weight exceeds the new bag capacity.
