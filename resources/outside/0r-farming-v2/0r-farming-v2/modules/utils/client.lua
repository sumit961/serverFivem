--[[ Contains client-side helper functions. ]]

local Utils = {}

---@param title string
---@param type "inform"|"error"|"success"|"warning"
---@param duration number
---@param description string
function Utils.notify(title, type, duration, description)
    lib.notify({
        title = title,
        type = type or "inform",
        duration = duration,
        description = description,
        position = "top-right",
    })
end

---@param text string
---@param options? TextUIOptions
function Utils.showTextUI(text, options)
    lib.showTextUI(text, options)
end

function Utils.hideTextUI()
    lib.hideTextUI()
end

---Change HUD visibility
---@param state boolean
function Utils.toggleHud(state)
    if shared.isResourceStart("0r-hud-v3") then
        exports["0r-hud-v3"]:ToggleVisible(state)
    else
        -- ? Your hud script export
    end
end

---@param plate string
---@param entity number
function Utils.giveVehicleKey(plate, entity)
    if shared.framework ~= "esx" then --[[Qb or Qbox]]
        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", plate)
    else
        -- ? Use your vehicle key script export
    end
end

function Utils.removeVehicleKey(plate, entity)
    -- ? Use your vehicle key script export
end

---@param entity number
---@param level number
function Utils.setFuel(entity, level)
    if not level then level = 100.0 end
    if shared.isResourceStart("LegacyFuel") then
        exports["LegacyFuel"]:SetFuel(entity, level)
    elseif shared.isResourceStart("x-fuel") then
        exports["x-fuel"]:SetFuel(entity, level)
    elseif shared.isResourceStart("ps-fuel") then
        exports["ps-fuel"]:SetFuel(entity, level)
    elseif shared.isResourceStart("ox_fuel") then
        Entity(entity).state.fuel = level
    else
        SetVehicleFuelLevel(entity, level)
        if DecorExistOn(entity, "_FUEL_LEVEL") then
            DecorSetFloat(entity, "_FUEL_LEVEL", level)
        end
    end
end

--[[!!! It is not recommended to change the functions from here on if you are not familiar with them !!!]]

---@param model string
---@param coords vector3
---@param rotation vector3
---@param freeze boolean
---@param isNetwork boolean
---@param doorFlag boolean
---@return integer
function Utils.createObject(model, coords, rotation, freeze, isNetwork, doorFlag)
    if freeze == nil then freeze = true end
    if isNetwork == nil then isNetwork = false end
    if doorFlag == nil then doorFlag = false end
    lib.requestModel(model)
    local object = CreateObject(model, coords.x, coords.y, coords.z, isNetwork, isNetwork, doorFlag)
    SetEntityCoords(object, coords.x, coords.y, coords.z, false, false, false, true)
    if rotation then
        if type(rotation) == "number" then
            rotation = vector3(0.0, 0.0, rotation)
        end
        SetEntityRotation(object, rotation.x, rotation.y, rotation.z, 2, false)
    end
    FreezeEntityPosition(object, freeze)
    SetModelAsNoLongerNeeded(model)
    return object
end

---@param coords vector3
function Utils.getGroundZ(coords)
    local x, y, z = table.unpack(coords)
    local groundCheckHeights = { z, z + 1.0, z + 2.0, z + 3.0, z + 4.0, z + 5.0 }

    for i, height in pairs(groundCheckHeights) do
        local foundGround, z = GetGroundZFor_3dCoord(x, y, height)

        if foundGround then
            return z, true
        end
    end

    return z, false
end

---@param target number|vector3
---@param options object
---@param route boolean
---@return number
function Utils.addBlip(target, options, route)
    local blip = type(target) == "number" and
        AddBlipForEntity(target) or
        AddBlipForCoord(vector3(target))

    SetBlipDisplay(blip, 4)
    SetBlipSprite(blip, options.sprite or 469)
    SetBlipColour(blip, options.color or 0)
    SetBlipScale(blip, options.scale or 0.85)
    SetBlipAsShortRange(blip, true)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(options.text or options.name or "Undefined")
    EndTextCommandSetBlipName(blip)

    if route then
        local coords = type(target) == "number" and GetEntityCoords(target) or vector3(target)
        SetNewWaypoint(coords.x, coords.y)
    end

    return blip
end

---@param coords vector3
---@param radius number
---@param options? object
---@return number
function Utils.addRadiusBlip(coords, radius, options)
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius + 0.0)

    SetBlipColour(blip, options and options.color or 1)
    SetBlipAlpha(blip, 100)
    SetBlipAsShortRange(blip, true)

    return blip
end

---@param coords vector3
---@param text string
function Utils.drawText3D(coords, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 70, 134, 123, 75)
    ClearDrawOrigin()
end

function Utils.progressBar(data)
    return lib.progressBar(data)
end

function Utils.skillCheck(difficulty, inputs)
    return lib.skillCheck(difficulty, inputs)
end

return Utils
