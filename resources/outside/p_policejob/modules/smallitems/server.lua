while not Config or not Config.SmallItems do
    Citizen.Wait(500)
end

if not Config.SmallItems.Enabled then
    return
end
