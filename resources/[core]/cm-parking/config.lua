CMParking = CMParking or {}

CMParking.Config = {
    Debug = false,

    Controls = {
        openKey = 'E'
    },

    Interaction = {
        distance = 3.0,
        parkVehicleDistance = 18.0,
        drawDistance = 25.0
    },

    Rules = {
        OwnerOnlyPark = true,
        AllowRetrieveFromAnyParking = false,
        LockVehicleWhenParked = true,
        WarpIntoVehicleOnRetrieve = false,
        DeleteVehicleWhenParked = true,
        UnlockOnRetrieve = true,
        StartEngineOnRetrieve = false
    },

    ParkingLots = {
        {
            id = 'legion_parking',
            label = 'Legion Parking',
            npc = 's_m_m_security_01',
            coords = vector4(215.86, -809.98, 30.73, 340.0),
            spawn = vector4(229.50, -800.22, 30.57, 160.0),
            radius = 28.0
        },
        {
            id = 'sandy_parking',
            label = 'Sandy Parking',
            npc = 's_m_m_security_01',
            coords = vector4(1737.45, 3710.90, 34.14, 20.0),
            spawn = vector4(1732.85, 3715.63, 34.12, 20.0),
            radius = 28.0
        }
    }
}
