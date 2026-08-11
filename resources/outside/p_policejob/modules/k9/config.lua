while not Config do Citizen.Wait(1) end

Config.K9 = {
    ---@field enabled: boolean [master toggle for the K9 feature]
    enabled = true,

    ---@field models: table [selectable dogs - list of { name: string, model: string, breed: string }]
    models = {
        { name = 'German Shepherd', model = 'a_c_shepherd', breed = 'german_shepherd' },
        { name = 'Retriever', model = 'a_c_retriever', breed = 'retriever' },
        { name = 'Rottweiler', model = 'a_c_rottweiler', breed = 'rottweiler' },
    },

    ---@field jobs: table [jobs allowed to spawn a K9 - { jobName = minGrade }]
    jobs = {
        ['police'] = 6, -- SIERZANT I
    },

    ---@field health: number [K9 max health]
    health = 200,

    ---@field armor: number [K9 armour]
    armor = 50,

    ---@field despawnDistance: number [auto-despawn the K9 if the handler wanders this far (metres) away]
    despawnDistance = 300.0,

    ---@field searchDistance: number [max distance (metres) between handler and target to allow a K9 search]
    searchDistance = 5.0,

    ---@field searchDuration: number [how long (milliseconds) the K9 sniffs a suspect before the search result]
    searchDuration = 6000,

    ---@field searchItems: table [item names the K9 flags as illegal when searching a suspect]
    searchItems = {
        'weed_brick',
        'cocaine_brick',
        'meth',
        'lockpick',
        'WEAPON_PISTOL',
    },
}
