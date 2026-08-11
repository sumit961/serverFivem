# CM Item Actions 2.7.2

- Normalized `RegisterItem`, `UnregisterItem`, `IsItemReady`, and
  `RegisterActionType` so both dot-style and colon-style FiveM export calls
  resolve the same arguments.
- Fixes `cm-doctor` medicine handlers remaining fail-closed even though all
  dependent resources were started.
