---
name: fivem-testing
description: Use for validating FiveM changes across static checks, server runtime checks, and manual gameplay testing.
---

# FiveM Testing

Separate results into **STATIC** (Lua syntax, `node --check`, manifests, `git diff --check`, `cm-validate`, and contract scanning), **SERVER RUNTIME** (restart changed resources, confirm command log, inspect new console, repair evidenced errors, repeat), and **MANUAL GAMEPLAY** (exact in-game steps, including routing buckets, OneSync, simultaneous operations, disconnect/reconnect, resource restart, and duplicate prevention when relevant). Never claim full testing from syntax or a clean console alone.
