-----------------For support, scripts, and more----------------
---------------- https://discord.gg/otstudios -----------------
---------------------------------------------------------------
Config = {}

Config.Framework = 'ESX' -- ESX | QBCORE | OX
Config.inventory = 'ESX' -- ESX | QBCORE | OX
Config.debug = false -- enables some debug prints
Config.target = false -- enable if using target/third-eye system
Config.targetSystem = 'ox_target' -- ox_target | qb-target | qtarget
Config.fareMin = 10 -- min possible number divided by ten to then be multiplied by distance of route then divided by ten again to work each fare payout - whole numbers only, no decimal points.
Config.fareMax = 15 -- max possible number divided by ten to then be multiplied by distance of route then divided by ten again to work each fare payout - whole numbers only, no decimal points.
Config.fuelPay = 0.5 -- Fuel compensation
Config.maxFares = 20 -- max fares that can be queued up
Config.NewFareTimer = 1 -- time in minutes that new fares are generated
Config.useOTSkills = false -- set to true if using OT_skills
Config.skillName = 'taxi' -- used with OT Skills integration 
Config.skillLabel = 'Taxi' -- used with OT Skills integration 
Config.skillDescription = 'start driving around peasants, before long you will be chauffeuring VIPs.' -- used with OT Skills integration 
Config.skillMaxlevel = 30 -- max skill level
Config.skillMultiplier = 1.5 -- increase this number to require more xp per level
Config.skillMaxReward = (15 * 8) -- max xp times 8 due to route bonus / only change first number in brackets.
Config.xpMin = 10 -- min xp per fare 
Config.xpMax = 15 -- max xp per fare
Config.chargeForTaxi = true -- enable / disable charging to rent taxi.
Config.givekey = false
Config.jobcheck = true
Config.job = 'taxi' -- job that can use taxi
Config.grade = 1 -- min grade for job
Config.CleanupOnDisconnect = true -- enable / disable vehicle deletion on player crash/disconnect


-- Add vehicles here you would like to have the ability to be used as taxi's
Config.Vehicles = {
    [`taxi`] = true
}


-- Define rewards for each level. (vehicle is only an option in the taxi rent menu)
Config.levels = {
    {
        reward = {},
        vehicle = `taxi`,
        vehicleLabel = 'Classic Taxi',
        vehicleRentCost = 1000,
        bonus = 1.0,
        label = 'Taxi License'
    },
    {
        reward = {type = 'item', name = 'water', amount = 2},
        bonus = 1.02,
        label = '2 bottles of water'
    },
    {
        reward = {type = 'money', name = 'money', amount = 3000},
        vehicle = `tempesta2`,
        vehicleLabel = 'Lamborghini Huracan',
        vehicleRentCost = 5000,
        bonus = 1.03,
        label = '$3000'
    }
}


-- Define taxi offices where players can go on/off duty and rent vehicles
Config.offices = {
    ['mirrorpark'] = {
        name = 'Mirror Park Taxi Office',
        coords = vector3(904.5, -173.92, 74.08),
        pedData = {
            coords = vector3(894.92, -179.12, 74.70),
            heading = 240.0,
            model = 'G_M_M_ChiBoss_01',
            gender = 'male'

        },
        blip = {
            sprite = 198,
            scale = 0.8,
            colour = 5
        },
        rentalSpawns = {
            vector4(899.08, -180.64, 73.22, 237.635),
            vector4(897.12, -183.51, 73.16, 237.635),
            vector4(908.81, -183.44, 73.56, 58.57),
            vector4(906.95, -186.48, 73.42, 58.57),
            vector4(905.15, -189.09, 73.23, 58.57)
        }
    }
}



