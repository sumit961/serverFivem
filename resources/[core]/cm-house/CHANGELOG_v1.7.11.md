# cm-house v1.7.11 — Family activity forwarding

- Every family-linked `LogHouse` entry is mirrored to cm-family's durable audit.
- Covers door lock/unlock, garage take/store/recall, storage access, weapon transfers, family house sale, eviction and deletion.
- Added server-only `AuditFamilyStorageTransfer` export for item-level cm-inventory deposit/withdraw logging.
- No client-controlled audit event was added.
- Successful admin property deletion now forwards `admin_delete_family_house` before the house cache is removed.
