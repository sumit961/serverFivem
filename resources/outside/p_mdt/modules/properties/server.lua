Properties = {
    data = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end
    Properties.data = Editable:getAllProperties()
end)

lib.callback.register("p_mdt/server/properties/fetch", function()
    return Properties.data
end)
