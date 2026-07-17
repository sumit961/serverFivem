# cm-family v1.1.9

## Founder authority and family chat fix

- Uses `cm_families.founder_cid` as the authoritative owner identity.
- Founder access no longer depends on legacy `cm_family_ranks.is_founder`.
- Creates a per-member effective founder rank, preventing authority from leaking to other members on the same rank.
- Repairs the founder membership to the highest rank on startup when legacy data points it to a lower rank.
- Guarantees the family founder can use family chat.
- Applies the same founder authority to family menus, bank, rank management, house management, and shared-vehicle controls that use `GetRankForCid`.
- Family player state reports the owner as founder on legacy schemas.
