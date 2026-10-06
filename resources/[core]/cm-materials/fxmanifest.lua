fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'CM Materials: read-only material catalog, production graph and economy rules (reference values, processing recipes, sources/sinks). Owns no items, inventory, crafting sessions or money; has no client surface.'
version '1.0.0'

dependencies {
    'cm-items',
}

shared_scripts {
    'shared/catalog.lua',
    'shared/graph.lua',
}

server_scripts {
    'server/main.lua',
}

-- Start order: cm-items, cm-inventory, cm-crafting, cm-materials, then gathering/processing content resources (Agent 3).
-- cm-materials never registers recipes itself: the resource that owns the station registers the definitions returned by
-- GetProcessingRecipes(stationType) with cm-crafting under its own (trusted) name.
