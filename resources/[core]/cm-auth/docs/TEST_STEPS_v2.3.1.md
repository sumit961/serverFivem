# cm-auth v2.3.1 Test Steps

## Start order
Use this order for foundation testing:

```cfg
restart cm-core
restart cm-auth
restart cm-playerdata
restart cm-characters
restart cm-climatime
restart cm-spawn
restart cm-hud
```

For `server.cfg`, make sure `cm-ui` starts before `cm-auth`:

```cfg
ensure cm-ui
ensure oxmysql
ensure cm-core
ensure cm-auth
ensure cm-playerdata
ensure cm-characters
ensure cm-climatime
ensure cm-spawn
ensure cm-hud
ensure cm-admin
```

## Auth UI checks
1. Join the server with no saved trusted token.
2. Confirm loading screen appears with blue/cyan CM styling.
3. Press `SPACE` to skip intro and confirm the auth UI opens.
4. Confirm the login/register/reset forms use the shared CM blue/cyan theme.
5. Confirm no black NUI background appears.
6. Confirm inputs, show/hide password buttons, remember-email checkbox, register link, reset link, and toast messages work.

## Login flow checks
1. Login with a valid account.
2. Confirm auth UI closes.
3. Confirm NUI focus is released.
4. Confirm character selector opens.
5. Confirm console does not spam normal login-success lines.

## Trusted login checks
1. Login successfully once.
2. Rejoin the server.
3. Confirm saved-login panel appears.
4. Click `Login as this account`.
5. Confirm the character selector opens.
6. Click `Use another account` on the next test and confirm the saved token is cleared locally.

## Register/reset checks
1. Register with missing fields and confirm validation toast appears.
2. Register with password shorter than 6 characters and confirm validation toast appears.
3. Register with mismatched passwords and confirm validation toast appears.
4. Test reset password using the same Rockstar/license profile linked to the account.
5. Confirm reset clears the trusted token and lets you login again.

## Production safety checks
1. Confirm `/loginui` does not work while `DEBUG = false`.
2. Confirm no FiveM blur/filter panel CSS is used in this resource.
3. Confirm normal restart does not print client loaded spam or login-success spam.
4. Confirm warnings/errors still print if MySQL or password hashing fails.
