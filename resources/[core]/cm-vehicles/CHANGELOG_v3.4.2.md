# cm-vehicles v3.4.2

- House garage/helipad placement vehicles now spawn in the requesting player's
  routing bucket, fixing invisible placement cars in MLO/private interiors.
- Scoped `cm-house` placement calls receive temporary owner access tied to the
  creator's character without granting broad vehicle-admin permission.
- Placement kind and routing bucket are recorded in the temporary vehicle registry.
- Vehicle integration contract updated to v2.1.0 with placement capabilities.

### Placement identity compatibility
- Temporary garage/helipad placement vehicles now accept string character IDs as well as numeric IDs. This prevents owner-bound placement cars from being rejected on frameworks whose character IDs contain prefixes or separators.
