# Bag level enforced

- `BuildClothingMetadata('bags', ...)` now always creates `metadata.bagLevel`.
- If no level is supplied by admin/catalog, it defaults to level 1.
- Bag level is clamped to 1-4.
- Inventory should use `metadata.bagLevel` to unlock bag slots/weight from its own config.
