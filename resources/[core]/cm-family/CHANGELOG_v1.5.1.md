# cm-family v1.5.1

- Replaces rank-specific overhead identity with one symbol and colour shared by the whole family.
- Moves symbol management from individual rank cards to the family overview.
- Adds Skull, Heart, Lightning, Moon, and Sun symbol choices.
- Adds automatic and manual additive schema migration for `cm_families.symbol`.
- Keeps legacy rank symbol columns intact for database compatibility, but they no longer control player identity.
- Makes family chat available to every active family member without a rank permission.
- Limits nearby family-member map blips to 100 metres and fixes client/server player ID state lookup.

