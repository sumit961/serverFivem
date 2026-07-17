# cm-house v1.7.3 — Public Admin Callback Fix

- Every connected player can open and use all cm-house admin sections in this development build.
- `Config.RequireAdmin` is disabled while `Config.DevelopmentPublicAdmin` remains enabled.
- Added client-side `/cmadmin`, `/cmadminhouse`, `/cmhouseadmin`, and `/houseadmin` aliases that request the panel directly.
- Fixed the admin-data callback crash caused by the removed `anchors` garage-customization variable.
- Replaced unsafe direct JSON decoding in admin template lists with the guarded decoder.
- Removed stale garage customization details from the admin UI.
- The public bypass does not grant ownership/access to normal house gameplay.
