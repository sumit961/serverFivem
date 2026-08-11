while not Config do Citizen.Wait(1) end

Config.Wardrobe = {
    ---@field Enabled: boolean [master toggle for the police wardrobe feature]
    Enabled = true,

    ---@field ManageGrade: number [minimum job grade required to create/manage shared outfits]
    ManageGrade = 9, -- PORUCZNIK I
}
