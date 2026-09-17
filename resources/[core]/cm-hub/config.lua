Config = {}

-- Keybind and command configuration
Config.DefaultKey = 'M'
Config.Command = 'hub'
Config.CommandAliases = { 'menu', 'm' }

-- General branding
Config.ServerName = 'CM Network'
Config.HubTitle = 'THANKS FOR JOINING'
Config.HubSubtitle = 'Welcome to the CM Network Hub. Access your dashboard below.'

-- Tactical Bento items
Config.BentoItems = {
    { id = 'daily_tasks', label = 'Daily Tasks', action = 'daily_tasks' },
    { id = 'premium_shop', label = 'Premium Shop', action = 'premium_shop' },
    { id = 'events', label = 'Unique Events', action = 'events' },
    { id = 'weekly_offers', label = 'Weekly Offers', action = 'weekly_offers' },
    { id = 'jobcenter', label = 'Job Center', action = 'jobcenter' },
    { id = 'organization', label = 'Org', action = 'organization' },
    { id = 'business', label = 'My Business', action = 'business' },
    { id = 'achievements', label = 'Achievements', action = 'achievements' },
    { id = 'family', label = 'My Family', action = 'family' },
    { id = 'inventory', label = 'Inventory', action = 'inventory' },
}

-- Minimal Bottom Actions
Config.BottomActions = {
    { id = 'clothes', label = 'Clothes', action = 'clothes' },
    { id = 'organization', label = 'Organization', action = 'organization' },
    { id = 'settings', label = 'Settings', action = 'settings' },
    { id = 'statistics', label = 'Statistics', action = 'statistics' },
    { id = 'contact_admin', label = 'Contact Admin', action = 'contact_admin' },
    { id = 'battlepass', label = 'Battlepass', action = 'battlepass' },
}

-- Civilian Careers / Job Center Catalog
-- Designed for easy addition of future jobs (e.g. delivery, mining, trucker, taxi)
Config.Jobs = {
    {
        id = 'electrician',
        title = 'Electrician',
        category = 'Infrastructure & Power',
        salary = '$5,000 / Task',
        badge = 'HIGH VOLTAGE',
        shortDesc = 'Maintain city power grids, diagnose switchboards, and respond to blackout emergencies.',
        description = 'Report to the Palmer-Taylor Power Plant to troubleshoot high-voltage switchboards. As your skill increases, rent the official company service truck to repair citywide junction boxes and restore power during blackout emergencies for major payouts.',
        locationName = 'Palmer-Taylor Power Plant',
        coords = { x = 718.72, y = 152.38, z = 80.74 },
        npcName = 'Frank Delgado (Chief Electrician)',
        image = 'images/jobs/electrician.jpg',
        levels = 'Level 1 - 3 (Switchboard -> Service Truck -> City Outages)',
        requirements = {
            'No prior license or experience required',
            'Government-inspected industrial job site',
            'Cash payroll paid directly upon task completion'
        },
        perks = {
            'Company Service Truck Rental',
            'Instant Cash Pay per Repair',
            'Skill Progression Tiers'
        }
    },
    {
        id = 'fishing',
        title = 'Commercial Fisher',
        category = 'Maritime & Aquaculture',
        salary = '$1,000 - $10,000+ / Haul',
        badge = 'OFFSHORE / COASTAL',
        shortDesc = 'Cast lines off piers or rent boats into deep ocean waters to harvest rare fish and sea life.',
        description = 'Visit the Vespucci Beach Marina tackle shop to equip specialized rods and bait. Catch common to legendary ocean species from the shore or rent speedboats and dinghies to venture into offshore channels for high-value trophy fish.',
        locationName = 'Vespucci Beach Pier & Marina',
        coords = { x = -1827.38, y = -1246.18, z = 13.02 },
        npcName = 'Vespucci Harbor Tackle Master',
        image = 'images/jobs/fishing.jpg',
        levels = 'Level 0 - 5 (Pier Angler -> Coastal -> Deep Ocean Hunter)',
        requirements = {
            'Fishing rod & bait (available at the tackle shop)',
            'Vespucci Beach dock access',
            'Civilian identification'
        },
        perks = {
            'Dockside Boat Rentals (Seashark / Dinghy)',
            'Sell Catches on the Spot for Clean Cash',
            'Trophy Catch Multipliers (Common up to Legend)'
        }
    }
}


