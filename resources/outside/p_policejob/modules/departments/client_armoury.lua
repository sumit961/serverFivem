Armoury = {
    antiSpam = GetGameTimer(),
    currentArmouryId = nil,
}

function Armoury.fetchPlayerJob()
    if Bridge.Framework.fetchPlayerJob then
        return Bridge.Framework.fetchPlayerJob()
    end
    return nil
end

function Armoury.canManage(self)
    local job = Armoury.fetchPlayerJob()
    if not job then
        return false
    end
    if not Config.Jobs[job.name] then
        return false
    end
    local manageGrade = Config.Armoury and Config.Armoury.ManageGrade or 0
    return job.grade >= manageGrade
end

function Armoury.enrichItems(items)
    if type(items) ~= "table" then
        return items
    end
    for _, item in ipairs(items) do
        local itemData = Bridge.Inventory.getItemData and Bridge.Inventory.getItemData(item.id)
        if itemData and itemData.image then
            item.image = itemData.image
        end
    end
    return items
end

function Armoury.open(self, armouryId)
    if self.antiSpam > GetGameTimer() then
        return
    end
    self.antiSpam = GetGameTimer() + 2000
    if type(armouryId) ~= "string" then
        return
    end
    local data = lib.callback.await("p_policejob/server/armoury/getItems", false, armouryId)
    if not data then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    self.currentArmouryId = armouryId
    SendNUIMessage({ action = "setVisibleArmoury", data = true })
    SendNUIMessage({ action = "setArmouryCategories", data = data.categories or {} })
    SendNUIMessage({ action = "setArmouryItems", data = Armoury.enrichItems(data.items) })
    SetNuiFocus(true, true)
end

function Armoury.close(self)
    self.antiSpam = GetGameTimer() + 2000
    self.currentArmouryId = nil
    SendNUIMessage({ action = "setVisibleArmoury", data = false })
    SetNuiFocus(false, false)
end

RegisterNUICallback("armoury/purchase", function(data, cb)
    if type(data) ~= "table" or not data.account or not data.items then
        cb(false)
        return
    end
    if not Armoury.currentArmouryId then
        cb(false)
        return
    end
    data.armouryId = Armoury.currentArmouryId
    local success = lib.callback.await("p_policejob/server/armoury/purchase", false, data)
    if success then
        local refreshed = lib.callback.await("p_policejob/server/armoury/getItems", false, Armoury.currentArmouryId)
        if refreshed then
            SendNUIMessage({ action = "setArmouryCategories", data = refreshed.categories or {} })
            SendNUIMessage({ action = "setArmouryItems", data = Armoury.enrichItems(refreshed.items) })
        end
    end
    cb(success)
end)

RegisterNUICallback("hideFrame", function(data, cb)
    local frameName = data and data.name
    if frameName == "setVisibleArmoury" then
        Armoury:close()
        cb("ok")
    end
end)

local manageContextId = "p_policejob_armoury_manage"
local manageItemContextId = "p_policejob_armoury_manage_item"
local manageLimitsContextId = "p_policejob_armoury_manage_limits"

function Armoury.fetchManageData(armouryId)
    return lib.callback.await("p_policejob/server/armoury/getManageData", false, armouryId)
end

function Armoury.showManageMenu(armouryId, manageData)
    local options = {}
    for itemIndex, item in ipairs(manageData.items) do
        local description
        if manageData.useStock then
            description = locale("armoury_manage_item_desc", item.stock)
        else
            description = locale("armoury_manage_item_desc_no_stock")
        end
        options[#options + 1] = {
            title = item.label or item.name,
            description = description,
            icon = "box",
            onSelect = function()
                Armoury.showManageItemMenu(armouryId, manageData, itemIndex)
            end,
        }
    end
    lib.registerContext({
        id = manageContextId,
        title = locale("armoury_manage_title"),
        options = options,
    })
    lib.showContext(manageContextId)
end

function Armoury.showManageItemMenu(armouryId, manageData, itemIndex)
    local item = manageData.items[itemIndex]
    if not item then
        return
    end
    local options = {}
    if manageData.useStock then
        options[#options + 1] = {
            title = locale("armoury_set_stock"),
            description = locale("armoury_current_stock", item.stock),
            icon = "warehouse",
            onSelect = function()
                local input = lib.inputDialog(locale("armoury_set_stock"), {
                    {
                        type = "number",
                        label = locale("armoury_stock"),
                        default = item.stock,
                        min = 0,
                        required = true,
                    },
                })
                if not input then
                    Armoury.showManageItemMenu(armouryId, manageData, itemIndex)
                    return
                end
                local success = lib.callback.await("p_policejob/server/armoury/setStock", false, armouryId, item.name, input[1])
                Bridge.Notify.showNotify(
                    success and locale("armoury_saved") or locale("armoury_save_failed"),
                    success and "success" or "error"
                )
                local refreshed = Armoury.fetchManageData(armouryId)
                if refreshed then
                    Armoury.showManageMenu(armouryId, refreshed)
                end
            end,
        }
    end
    options[#options + 1] = {
        title = locale("armoury_set_limits"),
        description = locale("armoury_set_limits_desc"),
        icon = "user-shield",
        onSelect = function()
            Armoury.showManageLimitsMenu(armouryId, manageData, itemIndex)
        end,
    }
    options[#options + 1] = {
        title = locale("back"),
        icon = "arrow-left",
        onSelect = function()
            Armoury.showManageMenu(armouryId, manageData)
        end,
    }
    lib.registerContext({
        id = manageItemContextId,
        title = item.label or item.name,
        menu = manageContextId,
        options = options,
    })
    lib.showContext(manageItemContextId)
end

function Armoury.showManageLimitsMenu(armouryId, manageData, itemIndex)
    local item = manageData.items[itemIndex]
    if not item then
        return
    end
    local options = {}
    for grade = 0, manageData.maxGrade do
        local limit = item.limits[tostring(grade)] or item.limits[grade]
        options[#options + 1] = {
            title = locale("armoury_grade_label", grade),
            description = limit and locale("armoury_grade_limit_current", limit) or locale("armoury_grade_limit_none"),
            icon = "shield-halved",
            onSelect = function()
                local input = lib.inputDialog(locale("armoury_grade_limit_title", grade), {
                    {
                        type = "number",
                        label = locale("armoury_grade_limit_input"),
                        description = locale("armoury_grade_limit_input_desc"),
                        default = limit,
                        min = 0,
                    },
                })
                local value = input and input[1] or nil
                local success = lib.callback.await("p_policejob/server/armoury/setLimit", false, armouryId, item.name, grade, value)
                Bridge.Notify.showNotify(
                    success and locale("armoury_saved") or locale("armoury_save_failed"),
                    success and "success" or "error"
                )
                local refreshed = Armoury.fetchManageData(armouryId)
                if refreshed then
                    Armoury.showManageLimitsMenu(armouryId, refreshed, itemIndex)
                end
            end,
        }
    end
    options[#options + 1] = {
        title = locale("back"),
        icon = "arrow-left",
        onSelect = function()
            Armoury.showManageItemMenu(armouryId, manageData, itemIndex)
        end,
    }
    lib.registerContext({
        id = manageLimitsContextId,
        title = item.label or item.name,
        menu = manageItemContextId,
        options = options,
    })
    lib.showContext(manageLimitsContextId)
end

function Armoury.openManage(self, armouryId)
    if not armouryId then
        return
    end
    local manageData = Armoury.fetchManageData(armouryId)
    if not manageData then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    Armoury.showManageMenu(armouryId, manageData)
end
