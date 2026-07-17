# cm-family v1.1.3

## Fixed

- Replaced the top-screen invite's blocking ox_lib response callback with a dedicated server event and client acknowledgement.
- Y is now detected on key press rather than release, avoiding FiveM team-chat consuming the Y release event.
- Added visible `Accepting invitation…` / `Declining invitation…` state.
- Added a 12-second response timeout instead of leaving the prompt silently locked.
- Every server validation and database result is returned to the invitation prompt.
- Added `/familyaccept` and `/familydecline` command fallbacks for players with custom key binds.
- Added server-side error logging for unexpected acceptance failures.
