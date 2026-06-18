# cm-auth v2.2.1 GTA IV UI + Trusted Login + 10-Tier RBAC

## Required order in `server.cfg`

```cfg
ensure oxmysql
ensure bcrypt
ensure cm-core
ensure cm-auth
ensure cm-characters
```

`cm-auth` already contains the loading screen. Do **not** run a separate loading-screen resource unless you intentionally replace this one.

---

## What this version adds

- GTA IV-inspired loading screen with:
  - `<audio autoplay loop>` background music
  - local slideshow image stack
  - Ken Burns style zoom/pan animation (`animate-gta-zoom`)
  - crossfade transitions
  - rotating hints
  - spacebar skip support
- New auth UI styled like the provided mockup
- Trusted-device token login:
  - first join still uses email/password
  - next join shows **Login as ...**
- Brute-force lockouts:
  - 5 failed attempts in 15 minutes
  - 30 minute lockout by email/IP
- No magic startup waits:
  - auth opens after `uiReady`
  - character selector opens from state-bag changes
- 10-tier dynamic RBAC admin system
- Admin identifier reset commands/events:
  - reset HWID
  - reset IP
  - reset Social Club / Rockstar license

---

## SQL structure

### `accounts` additions

```sql
ALTER TABLE accounts
ADD COLUMN auth_token VARCHAR(128) NULL,
ADD COLUMN auth_token_created_at DATETIME NULL,
ADD COLUMN admin_level TINYINT UNSIGNED NOT NULL DEFAULT 0;
```

### `login_attempts` (if you do not already have it)

```sql
CREATE TABLE IF NOT EXISTS login_attempts (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    ip_address VARCHAR(64) NULL,
    hwid_hash VARCHAR(255) NULL,
    success TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### `auth_lockouts`

```sql
CREATE TABLE IF NOT EXISTS auth_lockouts (
    lock_key VARCHAR(160) NOT NULL PRIMARY KEY,
    locked_until DATETIME NOT NULL,
    reason VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### `admin_ranks`

```sql
CREATE TABLE IF NOT EXISTS admin_ranks (
    `level` TINYINT UNSIGNED NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `permissions` JSON NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`level`)
);
```

### Example `admin_ranks` seed data

```sql
INSERT INTO admin_ranks (`level`, `name`, `permissions`) VALUES
(1, 'Helper', JSON_ARRAY('auth.lookup')),
(2, 'Trial Moderator', JSON_ARRAY('auth.lookup', 'auth.reset.ip')),
(3, 'Moderator', JSON_ARRAY('auth.lookup', 'auth.reset.ip', 'auth.reset.hwid')),
(4, 'Senior Moderator', JSON_ARRAY('auth.lookup', 'auth.reset.ip', 'auth.reset.hwid')),
(5, 'Administrator', JSON_ARRAY('auth.lookup', 'auth.reset.ip', 'auth.reset.hwid', 'auth.reset.socialclub')),
(6, 'Senior Admin', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(7, 'Head Admin', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(8, 'Community Manager', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(9, 'Developer', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(10, 'Owner', JSON_ARRAY('*'));
```

The resource also attempts to create/seed these automatically on start.

---

## RBAC behavior

On resource start:
- `admin_ranks` is loaded into a server-side memory cache named `RankCache`

On successful login:
- `accounts.admin_level` is read
- matching permissions are looked up from `RankCache`
- the following state bags are synced:
  - `adminLevel`
  - `adminRankName`
  - `adminPermissions`

Server helper available globally and as export:

```lua
HasPermission(src, 'auth.reset.hwid')
exports['cm-auth']:HasPermission(src, 'auth.reset.hwid')
```

Supported permission nodes in this version:
- `auth.lookup`
- `auth.reset.ip`
- `auth.reset.hwid`
- `auth.reset.socialclub`
- `auth.reset.identifiers`
- `auth.ranks.reload`
- `*`

---

## Admin reset tools

### Commands

```text
/authresethwid <accountId|email>
/authresetip <accountId|email>
/authresetsocialclub <accountId|email>
/authreloadranks
```

### Event

```lua
TriggerServerEvent('cm-auth:server:adminResetIdentifier', {
    target = 'player@example.com',
    field = 'hwid_hash' -- or ip_address / social_club_id
})
```

When an identifier is reset, the account's trusted auth token is also cleared.

---

## Important notes

- Trusted login does **not** automatically enter the account. It shows **Login as ...** first.
- Token login still checks Rockstar license and HWID.
- If the player clicks **Use another account**, the local token is removed.
- If you want to change permissions, edit the `admin_ranks` table and run `/authreloadranks`.
- If you want different loading images or music, replace files inside `loading/assets` and `loading/audio`.
