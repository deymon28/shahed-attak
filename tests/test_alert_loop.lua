package.path = './?.lua;' .. package.path
local played, muted = {}, false
local player = {index=1,valid=true,connected=true,force={index=1},print=function() end,
  play_sound=function(sound) played[#played+1]={path=sound.path,tick=game.tick} end}
local force = {index=1,valid=true,connected_players={player}}
game = {tick=10,get_player=function() return player end,connected_players={player}}
settings = {global={},get_player_settings=function() return {
  ['shahed-attack-alert-sound']={value=not muted},
  ['shahed-attack-verbose-alerts']={value=false}
} end}
local surface = {active_drones={},active_missiles={},alerted_events={}}
storage = {shahed_attack={surfaces={[1]=surface},alert_sound_events={},
  alert_counters={global_warning_dispatches=0}}}
local alerts = require('scripts.alerts')
local function tick(value) game.tick=value;alerts.flush_sounds(value) end
local drone = {event_id=1,entity={valid=true},target_force_index=1,mission='approach'}
surface.active_drones[100]=drone;surface.alerted_events[1]=true
alerts.air_raid(force,nil,1,'west',1,50)
tick(11);tick(370)
assert(#played==1,'do not overlap the first siren cycle')
tick(371)
assert(#played==2,'siren repeats without another detection event while the threat is alive')
tick(731)
assert(#played==3,'siren keeps repeating through a long approach')
drone.mission='returning'
tick(1091);tick(1200)
assert(#played==3,'returning recon does not sustain the siren')
surface.active_drones={}

local missile = {force_index=1,detected=true,intercepted=false,finished=false}
surface.active_missiles[2]=missile
game.tick=1210;alerts.ballistic(force,nil,45,{0,0},2,'east');tick(1211);tick(1481)
assert(#played==5 and played[5].path=='shahed-attack-ballistic-warning','ballistic warning repeats every full cycle')
missile.intercepted=true
tick(1751);tick(1800)
assert(#played==5,'intercepted missile does not leave a perpetual alarm')

missile.intercepted=false;missile.force_index=2
tick(1860)
assert(#played==5,'another force does not keep this player alarm active')
missile.force_index=1;missile.detected=false
tick(1920)
assert(#played==5,'undetected threats remain silent')
missile.detected=true
tick(1980)
assert(#played==6,'resume an already detected threat after loading or reconnecting')
muted=true;tick(2250);tick(2400)
assert(#played==6,'personal mute prevents repeated cycles')
muted=false;settings.global['shahed-attack-alert-delivery']={value='circuit-only'}
tick(2460)
assert(#played==6,'circuit-only prevents repeated cycles')
settings.global['shahed-attack-alert-delivery']={value='both'};player.connected=false
tick(2520)
assert(#played==6,'disconnected player stays silent')
player.connected=true;tick(2580)
assert(#played==7,'active warning resumes on reconnect')
surface.active_missiles={};tick(2850);tick(3000)
assert(#played==7,'removed threat ends the warning')
print('PASS: persistent warnings, exact repeat boundaries, threat cleanup, force isolation, mute and reconnect')
