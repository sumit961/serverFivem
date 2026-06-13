# cm-auth v2 Modern Bcrypt

## Required order in server.cfg

```cfg
ensure oxmysql
ensure bcrypt
ensure cm-core
ensure cm-auth
```

The bcrypt resource must expose `hash_sync` and `check_sync`, or compatible exports such as `hash`/`check`, `compare`, or `VerifyPassword`.

## What changed

- Login uses email + password only.
- Register uses email + password + retype password.
- UI remembers email locally when the checkbox is enabled.
- Eye buttons toggle password visibility.
- Wrong password and register errors show as glass toast notifications.
- `/loginui` is blocked after the player is already logged in.
- New passwords are saved with bcrypt.
- Old `TEMP_` hashes are only accepted when bcrypt is running, then migrated to bcrypt on successful login.

## Important

Do not use the old `TEMP_` password hash for public servers. Install and start bcrypt before cm-auth.
