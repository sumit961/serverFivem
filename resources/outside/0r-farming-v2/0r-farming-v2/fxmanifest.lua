fx_version "cerulean"
lua54 "yes"
game "gta5"
name "0r-farming-v2"
author "0resmon & alikoc.dev"
version "1.1.6"
description "Farming | alikoc.dev"

shared_scripts {
	"@ox_lib/init.lua",
	"config.lua",
	"shared/init.lua",
}

files {
	"locales/*.json",
	"modules/**/client.lua",
	"modules/bridge/init.lua",
	"core/**/config.lua",
	"ui/build/index.html",
	"ui/build/**/*",
}

client_scripts {
	"core/**/client_index.lua",
	"core/**/client.lua",
	"client.lua",
}

server_scripts {
	"@oxmysql/lib/MySQL.lua",
	"core/**/server_index.lua",
	"core/**/server.lua",
	"server.lua",
}

ui_page "ui/build/index.html"

dependencies { "ox_lib", "oxmysql", "0r_lib" }

escrow_ignore "**/*.lua"