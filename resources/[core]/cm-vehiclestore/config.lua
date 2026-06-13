CMVehicleStore = CMVehicleStore or {}

CMVehicleStore.Config = {
    Debug = false,
    PaymentAccount = 'cash', -- cash now; change to bank after cm-banking exists
    InteractionDistance = 2.4,

    Dealerships = {
        {
            id = 'pdm_cheap',
            label = 'Premium Deluxe Motorsport',
            npcName = 'Vehicle Dealer',
            ped = 'a_m_y_business_03',
            coords = vector4(-56.92, -1098.76, 26.42, 28.0),
            spawn = vector4(-45.78, -1082.44, 26.72, 69.0),
            vehicles = {
                { model = 'blista', label = 'Blista', category = 'Compact', price = 12000, trunkLevel = 1, description = 'Cheap city car with small trunk.' },
                { model = 'sultan', label = 'Karin Sultan', category = 'Sedan', price = 25000, trunkLevel = 3, description = 'Good starter RP car.' },
                { model = 'tailgater', label = 'Tailgater', category = 'Sedan', price = 35000, trunkLevel = 3, description = 'Comfort sedan with useful storage.' },
                { model = 'baller2', label = 'Baller SUV', category = 'SUV', price = 65000, trunkLevel = 4, description = 'Large SUV with bigger trunk.' },
                { model = 'speedo', label = 'Speedo Van', category = 'Van', price = 85000, trunkLevel = 6, description = 'Van with maximum trunk space.' },
                { model = 'bati', label = 'Bati 801', category = 'Bike', price = 18000, trunkLevel = 0, description = 'Fast bike with no trunk.' }
            }
        }
    }
}
