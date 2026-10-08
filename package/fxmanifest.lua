-- Written by the SIGF kit (common.ps1 Write-Manifest): do not edit, it is rewritten at every check.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'sigf_mod'
author 'SIGF'

ui_page 'lib/nui/hud.html'

shared_scripts {
  'lib/sh_bricks.lua',
}
client_scripts {
  'lib/cl_bricks.lua',
  'lib/cl_demo.lua',
  'client.lua',
  'demo.lua',
  'lib/cl_ready.lua',
}
server_scripts {
  'lib/sv_bricks.lua',
  'server.lua',
}
files {
  'lib/nui/*',
  'html/*',
  'img/*.png',
  'sfx/*.ogg',
}
files { 'stream/*.ytyp' }
data_file 'DLC_ITYP_REQUEST' 'stream/*.ytyp'
