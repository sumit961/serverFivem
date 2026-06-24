# Bag Metadata Minimal Update

- `BuildClothingMetadata()` now keeps bag metadata minimal.
- Bag inventory metadata keeps only `bagLevel`.
- Removed duplicate tooltip/admin helper metadata: `bag_level`, `backpackSlots`, `maxWeight`, `slots`, `weight`, etc.
- Bag capacity should be resolved by `cm-inventory` from `metadata.bagLevel` and its own `Config.BagLevels`.
- Default `clothing_bags` item weight set to `800` so inventory displays 0.8 kg when using gram-based weights.
