package.path = './?.lua;' .. package.path
local played, muted = {}, false
local player = {index=1,valid=true,connected=true,print=function() end,
  play_sound=function(sound) played[#played+1]=sound.path end}
local force = {valid=true,connected_players={player}}
game = {tick=10,get_player=function() return player end}
storage = {shahed_attack={alert_sound_events={},alert_counters={global_warning_dispatches=0}}}
settings = {global={},get_player_settings=function() return {
  ['shahed-attack-alert-sound']={value=not muted},
  ['shahed-attack-verbose-alerts']={value=false}
} end}
local alerts = require('scripts.alerts')
alerts.air_raid(force,nil,2,'west',1,50)
alerts.ballistic(force,nil,45,{0,0},2,'east')
alerts.flush_sounds(10)
assert(#played==0,'collect same-tick warnings')
alerts.flush_sounds(11)
assert(#played==1 and played[1]=='shahed-attack-ballistic-warning','ballistic warning has priority')
game.tick=20
alerts.ballistic(force,nil,45,{0,0},3,'east')
alerts.air_raid(force,nil,2,'west',4,50)
alerts.flush_sounds(21)
assert(#played==1,'staggered warning groups do not stack a playing clip')
game.tick=372
alerts.air_raid(force,nil,2,'west',7,50)
alerts.flush_sounds(373)
assert(#played==2 and played[2]=='shahed-attack-air-raid-siren','siren plays after cooldown')
game.tick=380
alerts.ballistic(force,nil,45,{0,0},8,'east')
alerts.flush_sounds(381)
assert(#played==3 and played[3]=='shahed-attack-ballistic-warning','ballistic escalation is immediate during drone siren')
game.tick=390
alerts.ballistic(force,nil,45,{0,0},9,'east')
alerts.flush_sounds(391)
assert(#played==3,'repeated ballistic warning shares the playing clip')
game.tick=750
alerts.ballistic(force,nil,45,{0,0},10,'east')
alerts.air_raid(force,nil,2,'west',11,50)
alerts.flush_sounds(751)
assert(#played==4 and played[4]=='shahed-attack-ballistic-warning','priority is independent of dispatch order')
game.tick=1120
alerts.air_raid(force,nil,2,'west',5,50)
muted=true
alerts.flush_sounds(1121)
assert(#played==4,'personal mute is respected at playback after cooldown')
muted=false
alerts.air_raid(force,nil,2,'west',1,50)
alerts.flush_sounds(1122)
assert(#played==4,'event deduplication survives coalescing')
settings.global['shahed-attack-alert-delivery']={value='circuit-only'}
alerts.ballistic(force,nil,45,{0,0},6,'east')
alerts.flush_sounds(1123)
assert(#played==4,'circuit-only mode stays silent')
print('PASS: warning priority, staggered cooldown, immediate escalation, deduplication and mute')
-- The durations match the shipped OGG clips: siren 6 s, ballistic warning 4.5 s.
settings.global['shahed-attack-alert-delivery']={value='both'}
storage.shahed_attack.alert_sound_playback={}
game.tick=2000
alerts.air_raid(force,nil,2,'west',20,50)
alerts.flush_sounds(2001)
local base_count=#played
for _,tick in ipairs({2271,2360}) do
 game.tick=tick-1
 alerts.air_raid(force,nil,2,'west',tick,50)
 alerts.flush_sounds(tick)
 assert(#played==base_count,'six-second siren must not overlap before its end')
end
game.tick=2360
alerts.air_raid(force,nil,2,'west',30,50)
alerts.flush_sounds(2361)
assert(#played==base_count+1,'siren can repeat at its exact six-second boundary')
game.tick=2400
alerts.ballistic(force,nil,45,{0,0},31,'east')
alerts.flush_sounds(2401)
base_count=#played
game.tick=2669
alerts.ballistic(force,nil,45,{0,0},32,'east')
alerts.flush_sounds(2670)
assert(#played==base_count,'ballistic warning remains gated at 269 ticks')
game.tick=2670
alerts.ballistic(force,nil,45,{0,0},33,'east')
alerts.flush_sounds(2671)
assert(#played==base_count+1,'ballistic warning can repeat at 270 ticks')
print('PASS: recorded warning duration boundaries')
