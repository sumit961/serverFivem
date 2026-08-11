-- Integration file with all ps-dispatch alerts exports

while not Config?.Dispatch do
    Citizen.Wait(100)
end

if Config.Dispatch.disableDispatch then
    return
end

local weaponTable = {
    [584646201]   = "CLASS 2: AP-Pistol",
    [453432689]   = "CLASS 1: Pistol",
    [3219281620]  = "CLASS 1: Pistol MK2",
    [1593441988]  = "CLASS 1: Combat Pistol",
    [-1716589765] = "CLASS 1: Heavy Pistol",
    [-1076751822] = "CLASS 1: SNS-Pistol",
    [-771403250]  = "CLASS 2: Desert Eagle",
    [137902532]   = "CLASS 2: Vintage Pistol",
    [-598887786]  = "CLASS 2: Marksman Pistol",
    [-1045183535] = "CLASS 2: Revolver",
    [911657153]   = "Taser",
    [324215364]   = "CLASS 2: Micro-SMG",
    [-619010992]  = "CLASS 2: Machine-Pistol",
    [736523883]   = "CLASS 2: SMG",
    [2024373456]  = "CLASS 2: SMG MK2",
    [-270015777]  = "CLASS 2: Assault SMG",
    [171789620]   = "CLASS 2: Combat PDW",
    [-1660422300] = "CLASS 4: Combat MG",
    [3686625920]  = "CLASS 4: Combat MG MK2",
    [1627465347]  = "CLASS 4: Gusenberg",
    [-1121678507] = "CLASS 2: Mini SMG",
    [-1074790547] = "CLASS 3: Assaultrifle",
    [961495388]   = "CLASS 3: Assaultrifle MK2",
    [-2084633992] = "CLASS 3: Carbinerifle",
    [4208062921]  = "CLASS 3: Carbinerifle MK2",
    [-1357824103] = "CLASS 3: Advancedrifle",
    [-1063057011] = "CLASS 3: Specialcarbine",
    [2132975508]  = "CLASS 3: Bulluprifle",
    [1649403952]  = "CLASS 3: Compactrifle",
    [100416529]   = "CLASS 4: Sniperrifle",
    [205991906]   = "CLASS 4: Heavy Sniper",
    [177293209]   = "CLASS 4: Heavy Sniper MK2",
    [-952879014]  = "CLASS 4: Marksmanrifle",
    [487013001]   = "CLASS 2: Pumpshotgun",
    [2017895192]  = "CLASS 2: Sawnoff Shotgun",
    [-1654528753] = "CLASS 3: Bullupshotgun",
    [-494615257]  = "CLASS 3: Assaultshotgun",
    [-1466123874] = "CLASS 3: Musket",
    [984333226]   = "CLASS 3: Heavyshotgun",
    [-275439685]  = "CLASS 2: Doublebarrel Shotgun",
    [317205821]   = "CLASS 2: Autoshotgun",
    [-1568386805] = "CLASS 5: GRENADE LAUNCHER",
    [-1312131151] = "CLASS 5: RPG",
    [125959754]   = "CLASS 5: Compactlauncher"
}

local function GetWeaponName()
    local currentWeapon = GetSelectedPedWeapon(cache.ped)
    return weaponTable[currentWeapon] or "Unknown"
end

local function GetVehicleData(vehicle)
    local data = {}

    local vehicleClass = {
        [0] = locale('compact'),
        [1] = locale('sedan'),
        [2] = locale('suv'),
        [3] = locale('coupe'),
        [4] = locale('muscle'),
        [5] = locale('sports_classic'),
        [6] = locale('sports'),
        [7] = locale('super'),
        [8] = locale('motorcycle'),
        [9] = locale('offroad'),
        [10] = locale('industrial'),
        [11] = locale('utility'),
        [12] = locale('van'),
        [17] = locale('service'),
        [19] = locale('military'),
        [20] = locale('truck')
    }

    data.class = vehicleClass[GetVehicleClass(vehicle)] or "Unknown"
    data.name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    data.plate = GetVehicleNumberPlateText(vehicle)
    data.id = NetworkGetNetworkIdFromEntity(vehicle)

    return data
end

local function GetPlayerGender()
    return GetEntityModel(cache.ped) == `mp_f_freemode_01` and locale('female') or locale('male')
end

local function GetStreetAndZone(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local zone = GetNameOfZone(coords.x, coords.y, coords.z)
    local zoneLabel = GetLabelText(zone)

    if crossingHash ~= 0 then
        local crossingStreet = GetStreetNameFromHashKey(crossingHash)
        street = street .. " / " .. crossingStreet
    end

    return street .. ", " .. zoneLabel
end

while not Base or not Base.exportHandler do
    Citizen.Wait(0)
end

Base:exportHandler('ps-dispatch', 'CustomAlert', function(data)
    if not data or not data.coords then return end
    
    local dispatchData = {
        message = data.message or "",
        codeName = data.dispatchCode or "NONE",
        code = data.code or '10-80',
        icon = data.icon or 'fas fa-question',
        priority = data.priority or 2, 
        coords = data.coords,
        gender = data.gender or nil,
        street = GetStreetNameFromHashKey(GetStreetNameAtCoord(data.coords.x, data.coords.y, data.coords.z)),
        camId = data.camId or nil,
        color = data.firstColor or nil,
        callsign = data.callsign or nil,
        name = data.name or nil, 
        vehicle = data.model or nil,
        plate = data.plate or nil,
        alertTime = data.alertTime or nil,
        doorCount = data.doorCount or nil,
        automaticGunfire = data.automaticGunfire or false,
        alert = {
            radius = data.radius or 0,
            sprite = data.sprite or 1,
            color = data.color or 1,
            scale = data.scale or 0.5,
            length = data.length or 2,
            sound = data.sound or "Lose_1st",
            sound2 = data.sound2 or "GTAO_FM_Events_Soundset",
            offset = data.offset or false,
            flash = data.flash or false
        },
        jobs = data.jobs or { 'police' },
    }
    TriggerServerEvent('ps-dispatch:server:notify', data)
end)

local function VehicleTheft()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetVehicleData(cache.vehicle)

    local dispatchData = {
        message = locale('vehicletheft'),
        codeName = 'vehicletheft',
        code = '10-35',
        icon = 'fas fa-car-burst',
        priority = 2,
        coords = coords,
        street = GetStreetAndZone(coords),
        vehicle = vehicle.name,
        plate = vehicle.plate,
        class = vehicle.class,
        alertTime = nil,
        jobs = { 'police' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end

Base:exportHandler('ps-dispatch', 'VehicleTheft', VehicleTheft)

local function Shooting()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('shooting'),
        codeName = 'shooting',
        code = '10-11',
        icon = 'fas fa-gun',
        priority = 2,
        coords = coords,
        street = GetStreetAndZone(coords),
        gender = GetPlayerGender(),
        weapon = GetWeaponName(),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'Shooting', Shooting)

local function Hunting()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('hunting'),
        codeName = 'hunting',
        code = '10-13',
        icon = 'fas fa-gun',
        priority = 2,
        weapon = GetWeaponName(),
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'Hunting', Hunting)

local function VehicleShooting()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetVehicleData(cache.vehicle)

    local dispatchData = {
        message = locale('vehicleshots'),
        codeName = 'vehicleshots',
        code = '10-60',
        icon = 'fas fa-gun',
        priority = 2,
        coords = coords,
        weapon = GetWeaponName(),
        street = GetStreetAndZone(coords),
        vehicle = vehicle.name,
        plate = vehicle.plate,
        class = vehicle.class,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'VehicleShooting', VehicleShooting)

local function SpeedingVehicle()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetVehicleData(cache.vehicle)

    local dispatchData = {
        message = locale('speeding'),
        codeName = 'speeding',
        code = '10-11',
        icon = 'fas fa-car',
        priority = 2,
        coords = coords,
        street = GetStreetAndZone(coords),
        vehicle = vehicle.name,
        plate = vehicle.plate,
        class = vehicle.class,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'SpeedingVehicle', SpeedingVehicle)

local function Fight()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('melee'),
        codeName = 'fight',
        code = '10-10',
        icon = 'fas fa-hand-fist',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'Fight', Fight)

local function PrisonBreak()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('prisonbreak'),
        codeName = 'prisonbreak',
        code = '10-90',
        icon = 'fas fa-vault',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'PrisonBreak', PrisonBreak)

local function StoreRobbery(camId)
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('storerobbery'),
        codeName = 'storerobbery',
        code = '10-90',
        icon = 'fas fa-store',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        camId = camId,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'StoreRobbery', StoreRobbery)

local function FleecaBankRobbery(camId)
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('fleecabank'),
        codeName = 'bankrobbery',
        code = '10-90',
        icon = 'fas fa-vault',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        camId = camId,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'FleecaBankRobbery', FleecaBankRobbery)

local function PaletoBankRobbery(camId)
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('paletobank'),
        codeName = 'paletobankrobbery',
        code = '10-90',
        icon = 'fas fa-vault',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        camId = camId,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'PaletoBankRobbery', PaletoBankRobbery)

local function PacificBankRobbery(camId)
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('pacificbank'),
        codeName = 'pacificbankrobbery',
        code = '10-90',
        icon = 'fas fa-vault',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        camId = camId,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'PacificBankRobbery', PacificBankRobbery)

local function VangelicoRobbery(camId)
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('vangelico'),
        codeName = 'vangelicorobbery',
        code = '10-90',
        icon = 'fas fa-gem',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        camId = camId,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'VangelicoRobbery', VangelicoRobbery)

local function HouseRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('houserobbery'),
        codeName = 'houserobbery',
        code = '10-90',
        icon = 'fas fa-house',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'HouseRobbery', HouseRobbery)

local function YachtHeist()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('yachtheist'),
        codeName = 'yachtheist',
        code = '10-65',
        icon = 'fas fa-house',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'YachtHeist', YachtHeist)

local function DrugSale()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('drugsell'),
        codeName = 'suspicioushandoff',
        code = '10-13',
        icon = 'fas fa-tablets',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'DrugSale', DrugSale)

local function SuspiciousActivity()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('susactivity'),
        codeName = 'susactivity',
        code = '10-66',
        icon = 'fas fa-tablets',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'SuspiciousActivity', SuspiciousActivity)

local function CarJacking(vehicle)
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetVehicleData(vehicle)

    local dispatchData = {
        message = locale('carjacking'),
        codeName = 'carjack',
        code = '10-35',
        icon = 'fas fa-car',
        priority = 2,
        coords = coords,
        street = GetStreetAndZone(coords),
        vehicle = vehicle.name,
        plate = vehicle.plate,
        class = vehicle.class,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'CarJacking', CarJacking)

local function InjuriedPerson()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('persondown'),
        codeName = 'civdown',
        code = '10-69',
        icon = 'fas fa-face-dizzy',
        priority = 1,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = 10,
        jobs = { 'ems' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'InjuriedPerson', InjuriedPerson)

local function DeceasedPerson()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('civbled'),
        codeName = 'civdead',
        code = '10-69',
        icon = 'fas fa-skull',
        priority = 1,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = 10,
        jobs = { 'ems' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'DeceasedPerson', DeceasedPerson)

local function OfficerDown()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('officerdown'),
        codeName = 'officerdown',
        code = '10-99',
        icon = 'fas fa-skull',
        priority = 1,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        name = Bridge.Framework.getPlayerName(),
        alertTime = 10,
        jobs = { 'ems', 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'OfficerDown', OfficerDown)

RegisterNetEvent("ps-dispatch:client:officerdown", function() OfficerDown() end)

local function OfficerBackup()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('officerbackup'),
        codeName = 'officerbackup',
        code = '10-32',
        icon = 'fas fa-skull',
        priority = 1,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        name = Bridge.Framework.getPlayerName(),
        alertTime = 10,
        jobs = { 'ems', 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'OfficerBackup', OfficerBackup)

RegisterNetEvent("ps-dispatch:client:officerbackup", function() OfficerBackup() end)

local function OfficerInDistress()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('officerdistress'),
        codeName = 'officerdistress',
        code = '10-99',
        icon = 'fas fa-skull',
        priority = 1,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        name = Bridge.Framework.getPlayerName(),
        alertTime = 10,
        jobs = { 'ems', 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'OfficerInDistress', OfficerInDistress)

local function EmsDown()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('emsdown'),
        codeName = 'emsdown',
        code = '10-99',
        icon = 'fas fa-skull',
        priority = 1,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        name = Bridge.Framework.getPlayerName(),
        alertTime = 10,
        jobs = { 'ems', 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'EmsDown', EmsDown)

RegisterNetEvent("ps-dispatch:client:emsdown", function() EmsDown() end)

local function Explosion()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('explosion'),
        codeName = 'explosion',
        code = '10-80',
        icon = 'fas fa-fire',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'Explosion', Explosion)

local function ArtGalleryRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('artgalleryrobbery'),
        codeName = 'artgalleryrobbery',
        code = '10-90',
        icon = 'fas fa-brush',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }
    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'ArtGalleryRobbery', ArtGalleryRobbery)

local function HumaneRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('humanelabsrobbery'),
        codeName = 'humanelabsrobbery',
        code = '10-90',
        icon = 'fas fa-flask-vial',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }
    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)

end
Base:exportHandler('ps-dispatch', 'HumaneRobbery', HumaneRobbery)

local function TrainRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('trainrobbery'),
        codeName = 'trainrobbery',
        code = '10-90',
        icon = 'fas fa-train',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }
    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)

end
Base:exportHandler('ps-dispatch', 'TrainRobbery', TrainRobbery)

local function VanRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('vanrobbery'),
        codeName = 'vanrobbery',
        code = '10-90',
        icon = 'fas fa-van-shuttle',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }
    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)

end
Base:exportHandler('ps-dispatch', 'VanRobbery', VanRobbery)

local function UndergroundRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('undergroundrobbery'),
        codeName = 'undergroundrobbery',
        code = '10-90',
        icon = 'fas fa-person-rays',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }
    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'UndergroundRobbery', UndergroundRobbery)

local function DrugBoatRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('drugboatrobbery'),
        codeName = 'drugboatrobbery',
        code = '10-65',
        icon = 'fas fa-ship',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'DrugBoatRobbery', DrugBoatRobbery)

local function UnionRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('unionrobbery'),
        codeName = 'unionrobbery',
        code = '10-90',
        icon = 'fas fa-truck-field',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'UnionRobbery', UnionRobbery)

local function CarBoosting(vehicle)
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetVehicleData(vehicle or cache.vehicle)

    local dispatchData = {
        message = locale('carboosting'),
        codeName = 'carboosting',
        code = '10-50',
        icon = 'fas fa-car',
        priority = 2,
        coords = coords,
        street = GetStreetAndZone(coords),
        vehicle = vehicle.name,
        plate = vehicle.plate,
        class = vehicle.class,
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'CarBoosting', CarBoosting)

local function SignRobbery()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('signrobbery'),
        codeName = 'signrobbery',
        code = '10-10',
        icon = 'fab fa-artstation',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo'}
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'SignRobbery', SignRobbery)

local function BobcatSecurityHeist()
    local coords = GetEntityCoords(cache.ped)

    local dispatchData = {
        message = locale('bobcatsecurity'),
        codeName = 'bobcatsecurityheist',
        code = '10-90',
        icon = 'fa-solid fa-building-shield',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo'}
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
Base:exportHandler('ps-dispatch', 'BobcatSecurityHeist', BobcatSecurityHeist)