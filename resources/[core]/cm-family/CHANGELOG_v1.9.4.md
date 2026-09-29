# cm-family v1.9.4

## Privacy hardening (priority audit follow-up)

- The replicated `cmFamily` player state no longer carries a member's full permission map. That state bag is broadcast to every connected client, not just the family in question, so any player could previously read any other online member's exact permission grants, rank tier, and custom title.
- The replicated payload is now limited to public identity fields already relied on elsewhere: family id/name/tag/color, overhead symbol fields, rank id/name/tier, founder flag, and custom title.
- Server-side family-permission enforcement is unchanged: every mutating action (invite/promote/demote/kick/transfer, bank, contributions, HQ, events) already resolves permissions from a live, server-side rank lookup and never read this replicated field for authorization.
- The family G-menu quick-action list (invite/promote/demote/kick/transfer shortcuts shown when targeting another player) can no longer pre-filter using a member's specific granted permission, since that data is no longer public. It still shows for family founders. A non-founder rank with an explicit permission grant can use the full family dashboard for the same action; every action remains independently permission-checked server-side.
- The owner-only "View Member Permissions" panel is unaffected -- it was already delivered through a dedicated, server-validated request/response path, not the replicated state bag.

No reward lifecycle, HQ progression, event engine, or contribution logic changed.
