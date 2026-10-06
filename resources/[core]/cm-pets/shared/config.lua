CM_PETS = CM_PETS or {}

CM_PETS.Config = {
    AdminPermission = 'players.manage',
    AdminInvokingResource = 'cm-admin',
    PlayerDataResource = 'cm-playerdata',
    AdminResource = 'cm-admin',

    Limits = {
        TypeId = 32,
        DisplayName = 64,
        Species = 32,
        Model = 64,
        Description = 255,
        CenterId = 32,
        CenterDisplayName = 64,
        CenterInteractionLabel = 64,
        PetName = 32,
        MetadataJson = 1024,
        MetadataKeys = 12,
        MetadataValue = 128,
    },

    Cooldowns = {
        OpenMs = 750,
        SummonMs = 1500,
        HideMs = 750,
        RenameMs = 1000,
        ModeMs = 500,
        AdoptionMs = 1500,
    },

    Adoption = {
        NpcStreamDistance = 80.0,
        MinInteractionDistance = 1.0,
        MaxInteractionDistance = 8.0,
        MaxRoutingBucket = 2147483647,
    },

    -- Adoption center NPCs are intentionally not configured here. An
    -- administrator must create a valid persisted center through the
    -- restricted exports after applying the manual SQL migration.
    ApprovedNpcModels = {
        s_f_y_shop_mid = true,
    },
    AdoptionCenters = {},

    -- Database catalog models must also be present here. Clients never choose
    -- a model; this table is the server-side approved model boundary.
    ApprovedModels = {
        a_c_retriever = { species = 'dog' },
        a_c_cat = { species = 'cat' },
        a_c_pug = { species = 'dog' },
    },

    Catalog = {
        {
            typeId = 'dog_retriever',
            displayName = 'Retriever',
            species = 'dog',
            model = 'a_c_retriever',
            description = 'A friendly cosmetic retriever companion.',
            enabled = true,
        },
        {
            typeId = 'cat_house',
            displayName = 'House Cat',
            species = 'cat',
            model = 'a_c_cat',
            description = 'A quiet cosmetic cat companion.',
            enabled = true,
        },
        {
            typeId = 'dog_pug',
            displayName = 'Pug',
            species = 'dog',
            model = 'a_c_pug',
            description = 'A small cosmetic pug companion.',
            enabled = true,
        },
    },
}
