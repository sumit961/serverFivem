# CM Stores v1.2 Inventory Fix

This version no longer marks normal items like water unavailable before purchase.
It only blocks virtual/system items such as phone and keys. Cash, weight, slots, and AddItem are checked after quantity confirmation.

Install: rename folder to `cm-stores` and place in `resources/[core]/`.

Server order:
```cfg
ensure cm-core
ensure cm-items
ensure cm-inventory
ensure cm-playerdata
ensure cm-stores
```

Restart:
```cfg
restart cm-stores
```
