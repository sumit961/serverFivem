# CM PlayerData Foundation Cleanup

This resource owns the loaded character cache for an online player.

## Owns

- Database character ID (`charId` / `characterId` / `rpId` state bag aliases)
- Loaded/unloaded character state
- Character first/last name and public name cache
- Cash and bank balances
- Money add/remove/set/check exports
- Money change events and transaction logs
- Health, armor, death, respawn, death details
- Player identity privacy, handshake, ID sharing, and G interaction menu

## Does not own

- Admin UI, staff ranks, permissions, or admin tools (`cm-admin`)
- Prices, payouts, fees, tax, or daily reward amounts (`cm-economy`)
- Playtime level/task unlock rules (`cm-progression`)
- Inventory item definitions (`cm-items` / `cm-inventory`)

## Main server exports

```lua
exports['cm-playerdata']:GetCharacterId(source)
exports['cm-playerdata']:GetCharacterData(source)
exports['cm-playerdata']:IsCharacterLoaded(source)
exports['cm-playerdata']:GetCharacterFullName(source)

exports['cm-playerdata']:GetMoney(source, 'cash')
exports['cm-playerdata']:GetMoney(source, 'bank')
exports['cm-playerdata']:GetAccounts(source)
exports['cm-playerdata']:CanAfford(source, 'cash', amount)
exports['cm-playerdata']:AddMoney(source, 'cash', amount, reason)
exports['cm-playerdata']:RemoveMoney(source, 'cash', amount, reason)
exports['cm-playerdata']:SetMoney(source, 'bank', amount, reason)
exports['cm-playerdata']:TransferMoney(source, 'cash', 'bank', amount, reason)
```

Legacy aliases are still kept:

```lua
GetCharId, IsLoaded, GetPlayerData, AddCash, RemoveCash, AddBank, RemoveBank
```

## Money rule

`cm-playerdata` stores/removes/adds the balance. `cm-economy` decides the amount.

Example shop flow:

```lua
local price = exports['cm-economy']:GetPrice('clothing', itemId)
if exports['cm-playerdata']:RemoveMoney(source, 'cash', price, 'clothing_purchase') then
    exports['cm-inventory']:AddItem(source, itemName, 1, metadata)
end
```

## Events

New clean events:

```lua
cm-playerdata:server:characterLoaded
cm-playerdata:client:characterLoaded
cm-playerdata:server:characterUnloaded
cm-playerdata:client:characterUnloaded
cm-playerdata:server:moneyChanged
cm-playerdata:client:moneyChanged
```

Legacy loaded/unloaded events are still fired for compatibility.

## Database additions

This cleanup keeps existing `characters.cash` and `characters.bank` columns for compatibility.
It also creates `economy_transactions` to audit balance changes.
