# cm-family v1.1.0

## Player G-menu
- Adds target-aware `Family` actions through cm-playerdata.
- Invite players while looking at them.
- Promote one rank, demote one rank, kick, or view family information.
- Every action is revalidated server-side for distance, loaded character IDs, membership, permissions, founder protection, and tier hierarchy.

## Family identity
- Adds a configurable family tag and colour.
- Adds global tag visibility, per-member tag hiding, and custom member titles.
- Publishes cached family identity through replicated player state for overhead labels without DB polling.
- Rank/tag/title changes refresh online members immediately.

## Family vehicles
- Vehicle menu lists all cars owned by the viewer plus family-shared cars.
- Cars must be parked in the authoritative family garage before sharing.
- Only the actual vehicle owner can share/unshare it.
- Authorized ranks can set the minimum family tier for a shared vehicle.
- Unsharing does not change or delete personal vehicle ownership.

## Family chat
- Adds `/f` and `/familychat`.
- Server resolves recipients by authoritative family membership.
- Supports rank permission `chat.family`, cooldown, length limits, and safe text cleanup.
- Emits `cm-family:server:chatMessage` and `cm-chat:server:familyMessage` for a custom cm-chat channel.
- Includes a standard `chat:addMessage` fallback.

## Database
- Adds `cm_families.tag_visible`.
- Adds `cm_family_members.custom_title` and `tag_hidden`.
- Startup schema repair remains non-destructive and legacy compatible.
- Manual fallback: `sql/008_family_identity_v1.1.0.sql`.
