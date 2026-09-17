---
name: fivem-database
description: Use for FiveM schema, migrations, oxmysql queries, transactions, persistence, startup validation, and recovery work.
---

# FiveM Database

Follow repository oxmysql conventions. Use parameterized queries, additive idempotent migrations, transactions for authoritative multi-step changes, and locks or idempotency for high-value operations. Normalize booleans safely, preserve administrator configuration, make recovery deterministic, and never destructively alter applied or unknown production data without approval.
