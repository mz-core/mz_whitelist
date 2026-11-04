fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_whitelist'
author 'Mazus'
description 'Whitelist de entrada server-side para a framework MZ'
version '1.0.0'

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'config.lua',
  'server/db.lua',
  'server/api.lua',
  'server/main.lua'
}

dependencies {
  'oxmysql',
  'mz_core'
}
