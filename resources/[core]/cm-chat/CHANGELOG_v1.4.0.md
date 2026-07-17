# cm-chat v1.4.0 — Authoritative family chat

- FAMILY tab is visible only while the player has an active `cmFamily` state.
- Messages sent from the FAMILY tab are routed through `cm-family` rather than generic group chat.
- `/f` and `/familychat` use the same rank permission, cooldown and recipient rules.
- Family messages render as `[TAG] [Rank/Title] Name (CID): message`.
- Family colour is used for the tab and message accent.
- The integration event is server-only and validates the author family state.
- Recipients are rebuilt from online players in the same authoritative family.
- Family chat messages are stored in `cm_chat_logs` with family metadata.
