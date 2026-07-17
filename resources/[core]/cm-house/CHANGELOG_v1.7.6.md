# cm-house v1.7.6

- Fixed family-house linking failing with `property_owner_is_not_in_that_family` after the founder membership had already been inserted.
- Removed the circular `cm-family -> cm-house -> cm-family` export verification during family creation.
- Calls originating directly from the configured authoritative `cm-family` resource now verify the exact `(character_id, family_id)` membership row in `cm_family_members`.
- Membership verification remains fail-closed on database errors and for all unauthorized callers.
- Other authorized non-admin integrations still use the configured `GetFamilyForCharacter` contract.
