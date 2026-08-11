while not Config do Citizen.Wait(1) end

-- Garage locations are defined in maps/departments/*.lua under `garages`.
Config.Garage = {
    ---@field Enabled: boolean [master toggle for the police garage feature]
    Enabled = true,

    ---@field maxDistance: number [max distance (metres) to interact with the garage ped/point]
    maxDistance = 10.0,

    ---@field CustomImages: table [optional per-model preview images, keyed by vehicle model = image URL]
    CustomImages = {
        -- ['police'] = 'https://example.com/police.jpg',
    },

    ---@field DefaultVehicleProperties: table [spawn props for job/addon fleet — Gabz PD uses modLivery (slot 48), not livery=0]
    DefaultVehicleProperties = {
        _default = {
            color1 = 0,
            color2 = 112,
            pearlescentColor = 0,
            wheelColor = 0,
            fuelLevel = 100.0,
            engineHealth = 1000.0,
            bodyHealth = 1000.0,
            windowTint = 1,
            modLivery = 1,
        },
        -- helikopter vanilla — klasyczne malowanie
        ['polmav'] = {
            color1 = 0,
            color2 = 0,
            pearlescentColor = 0,
            wheelColor = 0,
            fuelLevel = 100.0,
            engineHealth = 1000.0,
            bodyHealth = 1000.0,
            livery = 1,
        },
    },
}

--- Zwraca połączone właściwości spawnu dla modelu (addon Gabz: modLivery 1 = pierwsze malowanie LSPD).
---@param model string
---@return table|nil
function Config.Garage.GetVehicleProperties(model)
    local defaults = Config.Garage.DefaultVehicleProperties
    if not defaults then return nil end

    local props = {}
    if defaults._default then
        for key, value in pairs(defaults._default) do
            props[key] = value
        end
    end

    local override = defaults[model]
    if override then
        for key, value in pairs(override) do
            props[key] = value
        end
    end

    if not next(props) then return nil end
    return props
end
