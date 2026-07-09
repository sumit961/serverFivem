# cm-auth v2.3.1 CM UI Auth

## Required order in `server.cfg`

```cfg
ensure cm-ui
ensure oxmysql
ensure cm-core
ensure cm-auth
ensure cm-characters
```

`cm-auth` contains the loading screen and the email/password auth UI. It uses `cm-ui` for shared CM theme/components, so `cm-ui` must start before `cm-auth`. Do not run a second loading-screen resource unless you intentionally replace this one.

---

## What cm-auth owns

`cm-auth` owns only:

- Loading screen handoff
- Email/password register and login
- Trusted-device saved login token
- Login/register/reset rate limits and lockouts
- Account session state bags:
  - `accountId`
  - `accountEmail`
  - `isLoggedIn`
  - `authLoggedIn`
- Opening `cm-characters` after successful login

Admin menus, staff permissions, staff logs, and staff tools belong in `cm-admin`, not here.

---

## Password hashing

This version does **not** use an external bcrypt resource.

It tries FXServer native password hashing first:

```lua
local hash = GetPasswordHash('password')
local ok = VerifyPasswordHash('password', hash)
```

If your artifact does not provide those natives, it falls back to CM1 local salted iterative SHA-256. This keeps the resource working without a bcrypt export.

With `DEBUG = true`, boot self-test can show one of these messages:

```text
[CM-AUTH] Password hashing OK via FXServer native GetPasswordHash/VerifyPasswordHash | trusted-device login enabled
```

or:

```text
[CM-AUTH] Password hashing OK via CM1 local salted SHA-256 fallback | trusted-device login enabled
```

---

## SQL structure

`cm-auth` auto-creates/updates these auth helper tables/columns.

### `accounts` additions

```sql
ALTER TABLE accounts
ADD COLUMN auth_token VARCHAR(128) NULL,
ADD COLUMN auth_token_created_at DATETIME NULL;
```

### `login_attempts`

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

### `register_attempts`

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

`cm-auth` also tries to add unique indexes on `accounts.email` and `accounts.social_club_id`. If this fails, clean duplicate rows and restart.

---

## Trusted login

- First login uses email/password.
- Successful login creates a random saved-login token.
- The raw token is saved only on the client device.
- The database stores only a token hash.
- Token login still checks Rockstar license and HWID.
- Tokens expire after 30 days.

---

## Player password reset

The login UI includes **Forgot password?**. A player can reset a password only if their current Rockstar license matches the account owner.

Staff password/identifier reset should be implemented in `cm-admin` later using proper staff permissions and audit logs.

---

## Server exports

```lua
exports['cm-auth']:IsLoggedIn(source)
exports['cm-auth']:GetAccountId(source)
```

---

## Test checklist

1. Start server and confirm there are no password hashing warnings/errors.
2. Register a new account.
3. Login with the new account.
4. Confirm the auth UI closes.
5. Confirm `cm-characters` opens.
6. Rejoin and test saved login preview.
7. Click saved login and confirm character selector opens.
8. Try wrong password 5 times and confirm lockout.
9. Test forgot password from the same Rockstar license.
10. Confirm no bcrypt export error appears.
