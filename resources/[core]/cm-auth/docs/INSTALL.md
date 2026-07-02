# cm-auth v2.2.3 GTA IV UI + Trusted Login + 10-Tier RBAC

## Required order in `server.cfg`

```cfg
ensure oxmysql
ensure cm-core
ensure cm-auth
ensure cm-characters
```

`cm-auth` already contains the loading screen. Do **not** run a separate loading-screen resource unless you intentionally replace this one.

---

## Password hashing requirement

This version uses FXServer's built-in password hashing natives first:

```lua
local hash = GetPasswordHash('password')
local ok = VerifyPasswordHash('password', hash)
```

That means you do **not** need a separate `bcrypt` resource for `cm-auth`.
This fixes the common error where the console shows `bcrypt.Client.net` loaded,
but server-side login/register fails with `bcrypt export not found`.

If you still have an external `bcrypt` resource, it is now only optional fallback.
A client-only bcrypt resource is not enough because `cm-auth` hashes passwords on
the server.

On boot, cm-auth runs a hash+verify self-test and prints a line like:

```text
[CM-AUTH] Password hashing OK via FXServer native GetPasswordHash/VerifyPasswordHash ...
```

If that line does not appear, update your FiveM server artifacts.

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
  - 5 failed login attempts in 15 minutes
  - 3 account registrations per connection in 60 minutes
  - 30 minute lockout by email/IP (login lockouts also block register)
- Trusted-token hardening:
  - tokens are random 48-char strings, hashed (bcrypt) before storage
  - tokens expire after 30 days
- Duplicate-account protection via UNIQUE indexes on `email` and `social_club_id`
- Self-service password reset (proven by your Rockstar license) + admin override
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

### `register_attempts` (auto-created; used for register throttling)

```sql
CREATE TABLE IF NOT EXISTS register_attempts (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(64) NULL,
    hwid_hash VARCHAR(255) NULL,
    email VARCHAR(100) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_register_lookup (ip_address, hwid_hash, created_at)
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

Seed data lives in `sql/admin_ranks.sql`. The resource also attempts to
create/seed all of these automatically on start, and adds UNIQUE indexes on
`accounts.email` and `accounts.social_club_id` (clean any duplicates first if
the index fails to apply).

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
- `auth.reset.password`
- `auth.ranks.reload`
- `*`

---

## Admin reset tools

### Commands

```text
/authresethwid <accountId|email>
/authresetip <accountId|email>
/authresetsocialclub <accountId|email>
/authsetpassword <accountId|email> <newPassword>   (needs auth.reset.password)
/authreloadranks
```

### Forgot password (players)

The login screen has a **Forgot password?** link. A player can set a new
password **only** from the Rockstar account that owns it (the script verifies
`social_club_id`). If the account is on a different Rockstar profile, an admin
with `auth.reset.password` must run `/authsetpassword` instead.

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
