CMItems = CMItems or {}

-- Virtual/system items are NOT stored in cm-inventory.
-- They are registered here only so future resources can share labels/images/rules.
-- Example: cm-phone manages phones. cm-keys manages vehicle/house keys.
CMItems.VirtualItems = {
    phone = {
        label = 'Phone',
        image = 'phone.png',
        weight = 0,
        stack = false,
        unique = true,
        usable = true,
        close = false,
        category = 'virtual',
        inventory = false,
        virtual = true,
        system = 'cm-phone',
        description = 'Virtual phone account/device managed by cm-phone, not inventory.'
    },

    vehicle_key = {
        label = 'Vehicle Key',
        image = 'vehicle_key.png',
        weight = 0,
        stack = false,
        unique = true,
        usable = true,
        close = false,
        category = 'virtual',
        inventory = false,
        virtual = true,
        system = 'cm-keys',
        description = 'Virtual vehicle key managed by cm-keys, not inventory.'
    },

    house_key = {
        label = 'House Key',
        image = 'house_key.png',
        weight = 0,
        stack = false,
        unique = true,
        usable = true,
        close = false,
        category = 'virtual',
        inventory = false,
        virtual = true,
        system = 'cm-keys',
        description = 'Virtual house/property key managed by cm-keys, not inventory.'
    },

    business_key = {
        label = 'Business Key',
        image = 'business_key.png',
        weight = 0,
        stack = false,
        unique = true,
        usable = true,
        close = false,
        category = 'virtual',
        inventory = false,
        virtual = true,
        system = 'cm-business',
        description = 'Virtual business access managed by cm-business, not inventory.'
    }
}
