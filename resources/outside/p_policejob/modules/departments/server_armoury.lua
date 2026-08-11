Armoury = {}

local armouryFile = "armoury.json"
local savedData = {}
local purchaseLimits = {}
local armouryRegistry = {}

local function getArmouryItemData(itemName)
    if Bridge.Inventory and Bridge.Inventory.getItemData then
        local itemData = Bridge.Inventory.getItemData(itemName)
        if itemData then
            return itemData
        end
    end

    return {
        name = itemName,
        label = itemName,
        description = '',
    }
end

function Armoury.getDepartmentMaps()
    if type(Config.DepartmentMap) == "table" and Config.DepartmentMap then
        return Config.DepartmentMap
    end
    return { Config.DepartmentMap }
end

function Armoury.loadArmouriesFromMaps()
    local registry = {}
    for _, departmentMap in ipairs(Armoury.getDepartmentMaps()) do
        local departmentData = lib.load(("maps.departments.%s"):format(departmentMap))
        if type(departmentData) == "table" and type(departmentData.armouries) == "table" then
            for index, armouryConfig in ipairs(departmentData.armouries) do
                registry[("%s:%d"):format(departmentMap, index)] = armouryConfig
            end
        end
    end
    return registry
end

function Armoury.saveArmouryData()
    SaveResourceFile(
        GetCurrentResourceName(),
        armouryFile,
        json.encode(savedData, { indent = true }),
        -1
    )
end

function Armoury.ensureItemState(armouryId, itemConfig)
    if not savedData[armouryId] then
        savedData[armouryId] = {}
    end
    local itemState = savedData[armouryId][itemConfig.name]
    if not itemState then
        itemState = {
            stock = itemConfig.stock or Config.Armoury.DefaultStock,
            limits = {},
        }
        if type(itemConfig.limits) == "table" then
            for grade, limit in pairs(itemConfig.limits) do
                itemState.limits[tonumber(grade) or grade] = limit
            end
        end
        savedData[armouryId][itemConfig.name] = itemState
    end
    return itemState
end

function Armoury.findArmouryItem(armouryConfig, itemName)
    if not armouryConfig or type(armouryConfig.items) ~= "table" then
        return nil
    end
    for _, item in ipairs(armouryConfig.items) do
        if item.name == itemName then
            return item
        end
    end
    return nil
end

function Armoury.getMaxJobGrade(jobName)
    local jobs = Bridge.Framework.getJobs and Bridge.Framework.getJobs()
    if not jobs or not jobs[jobName] then
        return nil
    end
    local maxGrade = -1
    for grade in pairs(jobs[jobName]) do
        local numericGrade = tonumber(grade)
        if numericGrade and maxGrade < numericGrade then
            maxGrade = numericGrade
        end
    end
    if maxGrade >= 0 then
        return maxGrade
    end
    return nil
end

function Armoury.canManageArmoury(job)
    if not job or not Config.Jobs[job.name] then
        return false
    end
    local manageGrade = Config.Armoury.ManageGrade or 0
    return job.grade >= manageGrade
end

function Armoury.getRemainingLimit(armouryId, itemName, uniqueId, grade)
    local itemState = savedData[armouryId] and savedData[armouryId][itemName]
    if not itemState or not itemState.limits then
        return nil
    end
    local limit = itemState.limits[grade]
    if limit == nil then
        return nil
    end
    local purchased = 0
    if purchaseLimits[uniqueId] and purchaseLimits[uniqueId][armouryId] then
        purchased = purchaseLimits[uniqueId][armouryId][itemName] or 0
    end
    return math.max(0, limit - purchased)
end

function Armoury.initialize()
    armouryRegistry = Armoury.loadArmouriesFromMaps()
    local rawData = LoadResourceFile(GetCurrentResourceName(), armouryFile)
    if rawData and rawData ~= "" then
        local decoded = json.decode(rawData)
        if type(decoded) == "table" then
            savedData = decoded
        end
    end
    for armouryId, armouryConfig in pairs(armouryRegistry) do
        if type(armouryConfig.items) == "table" then
            for _, item in ipairs(armouryConfig.items) do
                Armoury.ensureItemState(armouryId, item)
            end
        end
    end
    Armoury.saveArmouryData()
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    Wait(100)
    Armoury.initialize()
end)

function Armoury.purchase(self, playerId, purchaseData)
    if not playerId or type(purchaseData) ~= "table" or not purchaseData.account or not purchaseData.items or not purchaseData.armouryId then
        return false
    end
    local armouryId = purchaseData.armouryId
    local armouryConfig = armouryRegistry[armouryId]
    if not armouryConfig then
        return false
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return false
    end
    local uniqueId = Bridge.Framework.getUniqueId(playerId)
    if not uniqueId then
        return false
    end
    local totalPrice = 0
    for _, cartItem in ipairs(purchaseData.items) do
        local itemConfig = Armoury.findArmouryItem(armouryConfig, cartItem.id)
        if not itemConfig then
            return false
        end
        if type(cartItem.quantity) ~= "number" or cartItem.quantity <= 0 then
            return false
        end
        local itemState = Armoury.ensureItemState(armouryId, itemConfig)
        if Config.Armoury.UseStock and itemState.stock < cartItem.quantity then
            Bridge.Notify.showNotify(playerId, locale("armoury_out_of_stock", itemConfig.name), "error")
            return false
        end
        local remainingLimit = Armoury.getRemainingLimit(armouryId, cartItem.id, uniqueId, job.grade)
        if remainingLimit ~= nil and remainingLimit < cartItem.quantity then
            Bridge.Notify.showNotify(playerId, locale("armoury_limit_reached", itemConfig.name), "error")
            return false
        end
        totalPrice = totalPrice + itemConfig.price * cartItem.quantity
    end
    local balances = Bridge.Framework.getMoney(playerId)
    if purchaseData.account == "society" then
        if not Bridge.Society or not Bridge.Society.getMoney or not Bridge.Society.removeMoney then
            Bridge.Notify.showNotify(playerId, locale("not_enough_money"), "error")
            return false
        end
        local societyBalance = Bridge.Society.getMoney(playerId, job.name) or 0
        if totalPrice > societyBalance then
            Bridge.Notify.showNotify(playerId, locale("not_enough_money"), "error")
            return false
        end
        if not Bridge.Society.removeMoney(playerId, job.name, totalPrice) then
            Bridge.Notify.showNotify(playerId, locale("not_enough_money"), "error")
            return false
        end
    else
        local balance = balances[purchaseData.account]
        if not balance or totalPrice > balance then
            Bridge.Notify.showNotify(playerId, locale("not_enough_money"), "error")
            return false
        end
        Bridge.Framework.removeMoney(playerId, purchaseData.account, totalPrice)
    end
    local purchasedSummary = {}
    for _, cartItem in ipairs(purchaseData.items) do
        Bridge.Inventory.addItem(playerId, cartItem.id, cartItem.quantity)
        if Config.Armoury.UseStock then
            local itemState = savedData[armouryId][cartItem.id]
            itemState.stock = math.max(0, itemState.stock - cartItem.quantity)
        end
        purchaseLimits[uniqueId] = purchaseLimits[uniqueId] or {}
        purchaseLimits[uniqueId][armouryId] = purchaseLimits[uniqueId][armouryId] or {}
        purchaseLimits[uniqueId][armouryId][cartItem.id] = (purchaseLimits[uniqueId][armouryId][cartItem.id] or 0) + cartItem.quantity
        purchasedSummary[#purchasedSummary + 1] = ("%sx %s"):format(cartItem.quantity, cartItem.id)
    end
    Armoury.saveArmouryData()
    if Config.Webhooks and Config.Webhooks.armoury and Config.Webhooks.armoury ~= "" then
        local playerName = Bridge.Framework.getPlayerName and Bridge.Framework.getPlayerName(playerId) or ("ID " .. playerId)
        Bridge.Logs.Send(
            playerId,
            "Armoury",
            ("%s purchased from %s for $%s (%s) - %s"):format(
                playerName, armouryId, totalPrice, purchaseData.account, table.concat(purchasedSummary, ", ")
            ),
            Config.Webhooks.armoury
        )
    end
    return true
end

function Armoury.buildShopData(armouryId, job, uniqueId)
    local armouryConfig = armouryRegistry[armouryId]
    if not armouryConfig then
        return {}, {}
    end
    local items = {}
    local categories = {}
    local seenCategories = {}
    for _, itemConfig in ipairs(armouryConfig.items) do
        local itemData = getArmouryItemData(itemConfig.name)
        local itemState = Armoury.ensureItemState(armouryId, itemConfig)
        local remainingLimit = Armoury.getRemainingLimit(armouryId, itemConfig.name, uniqueId, job.grade)
        local stock = Config.Armoury.UseStock and itemState.stock or -1
        if remainingLimit ~= nil then
            stock = stock == -1 and remainingLimit or math.min(stock, remainingLimit)
        end
        items[#items + 1] = {
            id = itemConfig.name,
            name = itemData.label,
            description = itemData.description,
            price = itemConfig.price,
            category = itemConfig.category,
            stock = stock,
        }
        if itemConfig.category and not seenCategories[itemConfig.category] then
            seenCategories[itemConfig.category] = true
            categories[#categories + 1] = itemConfig.category
        end
    end
    return items, categories
end

lib.callback.register("p_policejob/server/armoury/getItems", function(playerId, armouryId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] then
        return nil
    end
    local uniqueId = Bridge.Framework.getUniqueId(playerId)
    if not uniqueId then
        return nil
    end
    local items, categories = Armoury.buildShopData(armouryId, job, uniqueId)
    return {
        items = items,
        categories = categories,
        canManage = Armoury.canManageArmoury(job),
        useStock = Config.Armoury.UseStock,
    }
end)

lib.callback.register("p_policejob/server/armoury/purchase", function(playerId, purchaseData)
    return Armoury:purchase(playerId, purchaseData)
end)

lib.callback.register("p_policejob/server/armoury/getManageData", function(playerId, armouryId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Armoury.canManageArmoury(job) then
        return nil
    end
    local armouryConfig = armouryRegistry[armouryId]
    if not armouryConfig then
        return nil
    end
    local items = {}
    for _, itemConfig in ipairs(armouryConfig.items) do
        local itemState = Armoury.ensureItemState(armouryId, itemConfig)
        local itemData = getArmouryItemData(itemConfig.name)
        items[#items + 1] = {
            name = itemConfig.name,
            label = itemData and itemData.label or itemConfig.name,
            stock = itemState.stock,
            limits = itemState.limits or {},
        }
    end
    local maxGrade = Armoury.getMaxJobGrade(job.name) or job.grade
    return {
        items = items,
        playerGrade = job.grade,
        maxGrade = maxGrade,
        useStock = Config.Armoury.UseStock,
    }
end)

lib.callback.register("p_policejob/server/armoury/setStock", function(playerId, armouryId, itemName, stockAmount)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Armoury.canManageArmoury(job) then
        return false
    end
    local armouryConfig = armouryRegistry[armouryId]
    local itemConfig = Armoury.findArmouryItem(armouryConfig, itemName)
    if not itemConfig then
        return false
    end
    local stock = tonumber(stockAmount)
    if not stock or stock < 0 then
        return false
    end
    local itemState = Armoury.ensureItemState(armouryId, itemConfig)
    itemState.stock = math.floor(stock)
    Armoury.saveArmouryData()
    if Config.Webhooks and Config.Webhooks.armoury and Config.Webhooks.armoury ~= "" then
        Bridge.Logs.Send(
            playerId,
            "Armoury",
            ("Set stock of %s @ %s to %s"):format(itemName, armouryId, itemState.stock),
            Config.Webhooks.armoury
        )
    end
    return true
end)

lib.callback.register("p_policejob/server/armoury/setLimit", function(playerId, armouryId, itemName, grade, limitValue)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Armoury.canManageArmoury(job) then
        return false
    end
    local armouryConfig = armouryRegistry[armouryId]
    local itemConfig = Armoury.findArmouryItem(armouryConfig, itemName)
    if not itemConfig then
        return false
    end
    local gradeNumber = tonumber(grade)
    if not gradeNumber then
        return false
    end
    local itemState = Armoury.ensureItemState(armouryId, itemConfig)
    itemState.limits = itemState.limits or {}
    if limitValue == nil or limitValue == "" then
        itemState.limits[gradeNumber] = nil
    else
        local limit = tonumber(limitValue)
        if not limit or limit < 0 then
            return false
        end
        itemState.limits[gradeNumber] = math.floor(limit)
    end
    Armoury.saveArmouryData()
    if Config.Webhooks and Config.Webhooks.armoury and Config.Webhooks.armoury ~= "" then
        Bridge.Logs.Send(
            playerId,
            "Armoury",
            ("Set grade %s limit of %s @ %s to %s"):format(
                gradeNumber, itemName, armouryId, tostring(itemState.limits[gradeNumber])
            ),
            Config.Webhooks.armoury
        )
    end
    return true
end)

AddEventHandler("playerDropped", function()
    local playerId = source
    local uniqueId = Bridge.Framework.getUniqueId and Bridge.Framework.getUniqueId(playerId)
    if uniqueId then
        purchaseLimits[uniqueId] = nil
    end
end)
