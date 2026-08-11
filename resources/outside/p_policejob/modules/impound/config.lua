while not Config do Citizen.Wait(1) end

Config.Impound = {
    ---@field Enabled: boolean [master toggle for the impound feature]
    Enabled = true,

    ---@field UseGarageExport: boolean [if true use the export from your garage script when compatible]
    UseGarageExport = true,

    ---@field VehicleState: table [how your garage database marks a vehicle as impounded/released - garage scripts differ (`stored`, `state`, `garage`, `in_garage`, ...)]
    VehicleState = {
        ---@field mode: string ['auto' = framework default from p_bridge (ESX: `stored`, QB/Qbox: `state`) | 'custom' = the functions below | 'none' = never touch the vehicle row (your garage script handles impound state itself)]
        mode = 'auto',

        ---EDITABLE: called on the server when a vehicle is impounded (only when mode = 'custom')
        ---@param plate string [normalized vehicle plate]
        onImpound = function(plate)
            -- example for a garage script where a NULL `garage` column hides the vehicle:
            -- MySQL.update.await('UPDATE owned_vehicles SET garage = NULL WHERE plate = ?', { plate })
        end,

        ---EDITABLE: called on the server when a vehicle is paid out / released (only when mode = 'custom')
        ---@param plate string [normalized vehicle plate]
        onRelease = function(plate)
            -- example: put the vehicle back into a default garage so it shows up in the garage menu again:
            -- MySQL.update.await('UPDATE owned_vehicles SET garage = ? WHERE plate = ?', { 'Legion', plate })
        end,
    },

    ---@field Time: number [time (seconds) it takes to impound a vehicle]
    Time = 20,

    ---@field UnownedVehicles: table [what happens when an officer tries to impound a vehicle without a registered owner]
    UnownedVehicles = {
        ---@field remove: boolean [if true the vehicle is simply removed (deleted) with a progress bar instead of opening the impound form]
        remove = true,
        ---@field removeTime: number [remove progress bar duration in milliseconds]
        removeTime = 5000,
    },

    ---@field Locations: table [impound lot locations, keyed by a unique name]
    Locations = {
        ['Los_Santos'] = {
            ---@field label: string [display name of the impound lot]
            label = 'Los Santos Impound Lot',
            ---@field ped: table [attendant ped - { model: string, anim: { dict: string, name: string, flag: number } }]
            ped = {
                model = 's_m_y_hwaycop_01',
                anim = {dict = 'amb@world_human_cop_idles@male@base', name = 'base', flag = 1},
            },
            ---@field coords: vector4 [position + heading of the ped and target]
            coords = vector4(409.2483, -1622.8567, 29.2919, 227.7229),
        }
    },

    ---@field Photo: table [vehicle photo capture (reuses the police camera/screenshot upload pipeline configured in config/server.lua)]
    Photo = {
        ---@field enabled: boolean [allow officers to attach a photo of the impounded vehicle]
        enabled = true,
        ---@field required: boolean [if true, a photo must be taken before the form can be submitted]
        required = false,
    },

    ---@field Offences: table [preset offence suggestions shown in the impound form (officers can still type a custom one)]
    Offences = {
        'Illegal parking',
        'Abandoned vehicle',
        'Reckless / dangerous driving',
        'No valid insurance',
        'Involved in a crime',
        'Stolen vehicle recovery',
        'Unpaid fines',
        'Evading police',
    },

    ---@field MDT: table [optional integration that pushes the full impound record (incl. photo) into an MDT resource]
    MDT = {
        ---@field enabled: boolean [master toggle - the push below only runs when this is true AND `resource` is started]
        enabled = false,

        ---@field resource: string [name of the MDT resource to detect via GetResourceState]
        resource = 'p_mdt',

        ---EDITABLE: called on the server right after a vehicle is impounded, but ONLY when the resource above is started.
        ---@param record table [{ plate, owner, model, officerName, officerId, offence, notes, price, impoundedAt, releaseAt, photo, location }]
        push = function(record)
            
        end,
    },

    ---@field OnVehicleImpounded: function [called when a vehicle is impounded - (officerId: number, plate: string, reason: string)]
    OnVehicleImpounded = function(officerId, plate, reason)
    end,

    ---@field OnVehiclePayedOut: function [called when a vehicle is paid out/retrieved - (playerId: number, plate: string, amount: number)]
    OnVehiclePayedOut = function(playerId, plate, amount)
    end,
}
