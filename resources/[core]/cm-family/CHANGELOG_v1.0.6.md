# cm-family v1.0.6

## Fixed

- Fixed `house_link_failed:property_owner_is_not_in_that_family` during family creation.
- The founder membership is now added to `MemberByCid` immediately after its database insert and before `cm-house:SetFamilyHouseLink` performs its synchronous callback into `GetFamilyForCharacter`.
- Added a local membership sanity check before linking the property.
- Existing guarded rollback clears the provisional cache entry and deletes family rows if linking fails.
