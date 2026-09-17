-- Adapt the supplied 3core locations to the CM parking contract.
Config.Price = 2500
Config.InteractionDistance = 3.0
Config.VehicleDistance = 8.0

Config.Ownership = {
    enabled = true,
    purchasePrice = 250000,
    ownerRevenuePercent = 80,
    tiers = {
        low = 1000,
        normal = 2500,
        high = 5000
    },
    defaultTier = 'normal'
}

for index, parking in ipairs(Config.Parking or {}) do
    parking.id = ('public_%d'):format(index)
    parking.label = parking.Name or ('Public Parking %d'):format(index)
    parking.blip = parking.Blip and parking.Blip.Coords or parking.Npc.Coords
    parking.npc = parking.Npc.Coords
    parking.spots = parking.ParkSpots or {}
end
