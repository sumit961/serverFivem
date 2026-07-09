# cm-auth v2.3.1-cm-ui-auth Changelog

## Updated
- Added `cm-ui` as a resource dependency in `fxmanifest.lua`.
- Updated the login/register/reset NUI page to load the shared CM theme and component files:
  - `nui://cm-ui/web/cm-theme.css`
  - `nui://cm-ui/web/cm-components.css`
  - `nui://cm-ui/web/cm-ui.js`
- Replaced duplicated local purple button/card/input styling with shared `cm-ui` classes where safe.
- Kept only auth-specific layout, hero art placement, scene overlay, and responsive positioning inside `ui/style.css`.
- Updated auth colors to the central blue/cyan CM variables from `cm-ui`.
- Updated loading screen styling to use CM theme variables and shared progress/card component classes.
- Reused `CMUI.toast()` for auth notifications when `cm-ui` is available, with a local fallback for safety.

## Cleaned
- Removed external Google Fonts imports from auth/loading CSS to avoid unnecessary NUI network requests.
- Removed direct successful-login console spam; successful logins still go through `cm-core` logging for admin/audit use.
- Gated the manual `/loginui` test command behind `DEBUG` so it is not available in production.
- Removed normal client startup console spam.
- Kept warnings/errors visible for real problems like database failures or password hashing failure.

## Not Changed
- Login/register/reset/trusted-token logic was not rewritten.
- Database schema and auth security rules were not changed.
- Character selector handoff was not changed.
- Money, admin logic, and character data remain outside `cm-auth`.
