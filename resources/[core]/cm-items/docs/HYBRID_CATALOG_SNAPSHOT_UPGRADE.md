# Hybrid Catalog Snapshot Upgrade

Clothing admin inventory items now use a hybrid design:

- `clothing_catalog` stays the source of truth.
- `inventory_items.metadata.catalogId` links an owned item to the catalog row.
- `inventory_items.metadata.snapshot` keeps a small fallback for label/image/bag level if the catalog row is later hidden or deleted.

This avoids duplicating large clothing metadata on every owned item while keeping old items safe.
