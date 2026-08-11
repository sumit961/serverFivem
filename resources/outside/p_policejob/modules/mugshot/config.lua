while not Config do Citizen.Wait(1) end

-- Mugshot points (coords/cameras) are defined in maps/departments/*.lua under `mugshots`.
Config.Mugshot = {
    ---@field enabled: boolean [master toggle for the mugshot feature]
    enabled = true,

    ---@field boardTitle: string [top line printed on the mugshot board]
    boardTitle = 'SUSPECT',

    ---@field boardSubtitle: string [bottom line printed on the mugshot board]
    boardSubtitle = 'LSPD',

    ---@field SendPhoto: function [SERVER - posts the mugshot to Discord - (data: table with id, suspect, dob, officer, description, url, webhook)]
    SendPhoto = function(data)
        if not data.webhook or data.webhook == '' then return end

        local embeds = {
            {
                ['avatar_url'] = 'https://r2.fivemanage.com/xlufCGKYLtGfU8IBmjOL9/360.png',
                ['username'] = 'MUGSHOT - LSPD',
                ['author'] = {
                    ['name'] = 'MUGSHOT',
                    ['icon_url'] = 'https://r2.fivemanage.com/xlufCGKYLtGfU8IBmjOL9/360.png',
                },
                ['description'] = ('Mugshot ID: **%s**\nSuspect: **%s**\nDOB: **%s**\nOfficer: **%s**\nDescription: **%s**'):format(
                    data.id, data.suspect, data.dob, data.officer, data.description
                ),
                ['type'] = 'rich',
                ['color'] = 5793266,
                ['image'] = { ['url'] = data.url },
                ['footer'] = {
                    ['text'] = os.date(),
                    ['icon_url'] = 'https://r2.fivemanage.com/xlufCGKYLtGfU8IBmjOL9/360.png',
                },
            }
        }

        PerformHttpRequest(data.webhook, function() end, 'POST', json.encode({
            username = 'MUGSHOT',
            avatar_url = 'https://r2.fivemanage.com/xlufCGKYLtGfU8IBmjOL9/360.png',
            embeds = embeds
        }), { ['Content-Type'] = 'application/json' })
    end,

    ---@field onPhotoTaken: function [CLIENT - called when a mugshot is taken - (url: string)]
    onPhotoTaken = function(url) end,

    ---@field onPhotoRemoved: function [SERVER - called when a mugshot is removed - (playerId: number, mugshotId: any)]
    onPhotoRemoved = function(playerId, mugshotId) end,
}
