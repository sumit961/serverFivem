# cm-family v1.2.1 — Complete G-menu member management

- Public family profile is viewable from another player’s G menu, including family identity, founder, linked house, member count, online count, and the selected member’s public rank/title.
- Family owner can inspect a same-family member’s effective permissions from the G menu. Sensitive bank/log data is not exposed.
- Promote and demote move exactly one configured rank and notify both the manager and target with old/new rank names.
- Kick notifies the manager and removed member.
- Ownership transfer is owner-only and requires a server-issued, expiring confirmation token plus a second proximity/character validation after the dialog.
- Server protections block equal/higher-rank management, founder kicks/rank changes, cross-family actions, and promotion to the manager’s own rank or above.
- Leadership transfer updates both memberships and founder_cid in one database transaction.
