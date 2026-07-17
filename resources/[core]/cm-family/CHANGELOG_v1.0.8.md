# cm-family v1.0.8 — Family House Authority

- Added the protected `FinalizeHouseFamilyDeletion` export for `cm-house`.
- Selling, evicting or deleting the linked family house now clears family runtime caches and online player family markers.
- Members are notified when the family is disbanded by a property lifecycle action.
- Startup enforces that every family remains linked to a real house owned by one of its members.
- Orphan family rows left by older builds are removed with child-first transactional cleanup.
- Family house IDs are normalized when loaded into cache.
