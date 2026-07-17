# cm-family v1.1.2

- Fixed `client/cl_invites.lua:100: attempt to index a nil value` after pressing Y.
- The invite renderer now re-snapshots `activeInvite` after every `Wait(0)` before indexing it.
- Invitation responses use a stable invite object so a late response cannot close a newer invitation.
- Wrapped the ox_lib callback in `pcall` so callback failures show an error notification instead of killing the client thread.
- Y and N continue to use the same server-authoritative invitation response callback.
