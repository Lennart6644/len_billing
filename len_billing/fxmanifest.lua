fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'len_billing'
description 'Billing System - Ausstellen, Bezahlen, Posten, Export, Stornieren'
version '2.2.0'

dependencies {
    'es_extended',
    'oxmysql',
    'ox_inventory',
}

shared_scripts {
    'config.lua',
    'locales/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core.lua',
    'server/exports.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}
