# Central intake configuration

CM Prison 2.1 owns one shared intake location, cell spawn pool, and release
point for every CM Law organization. It creates `cm_prison_settings` on first
start and migrates legacy shared jail spawns and release data when available.

Use the prison admin location controls to set or reset `intake`, `spawn`, and
`release`. The resource broadcasts configuration changes so clients refresh
the one intake NPC without a restart.
