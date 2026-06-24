CMStoreBase = CMStoreBase or {}

CMStoreBase.Config = {
    Debug = true,

    OpenKey = 38, -- E
    DefaultPointDistance = 2.0,
    DefaultDrawDistance = 12.0,

    ForceHighPriceWhenUnowned = true,

    DefaultPed = {
        enabled = true,
        model = 'mp_m_shopkeep_01',
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        freeze = true,
        invincible = true,
        blockEvents = true
    },

    DefaultBlip = {
        enabled = false,
        sprite = 52,
        color = 2,
        scale = 0.75,
        label = 'Store'
    },

    DefaultImage = 'images/default.svg',

    -- Adapter functions keep this resource independent from your framework.
    -- Change these only if your cm-core / cm-inventory export names are different.
    ServerAdapters = {
        RemoveMoney = function(source, amount, account)
            account = account or 'cash'

            local ok, result = pcall(function()
                return exports['cm-core']:RemoveMoney(source, account, amount)
            end)
            if ok and result ~= nil then return result == true end

            ok, result = pcall(function()
                return exports['cm-core']:RemoveCash(source, amount)
            end)
            if ok and result ~= nil then return result == true end

            print(('[cm-storebase] No working money adapter. Source %s tried to pay $%s.'):format(source, amount))
            return false
        end,

        AddItem = function(source, itemName, quantity, metadata)
            metadata = metadata or {}

            local ok, result = pcall(function()
                return exports['cm-inventory']:AddItem(source, itemName, quantity, metadata)
            end)
            if ok and result ~= nil then return result == true end

            TriggerEvent('cm-inventory:server:addItem', source, itemName, quantity, metadata)
            return true
        end
    }
}
