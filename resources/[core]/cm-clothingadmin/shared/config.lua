CMClothingAdmin = CMClothingAdmin or {}

CMClothingAdmin.Config = {
    -- v7 dev mode: every player can open/use the clothing admin UI.
    -- Later set RequireAce = true and add:
    -- add_ace group.admin cm.clothingadmin allow
    RequireAce = false,
    AcePermission = 'cm.clothingadmin',
    AllowConsole = true,

    -- true  = save current texture only.
    -- false = save drawable default for all textures (texture_id = -1).
    SaveTextureSpecificByDefault = true,

    DefaultShop = 'city',
    DefaultCategory = 'uncategorized',

    Categories = {
        'hoodies', 'shirts', 'jackets', 'pants', 'shoes', 'hats',
        'glasses', 'chains', 'bags', 'watches', 'earrings', 'uniforms', 'vip'
    },

    Shops = {
        'city', 'budget', 'luxury', 'police', 'gang', 'vip', 'default'
    }
}
