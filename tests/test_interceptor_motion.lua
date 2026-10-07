package.path='./?.lua;'..package.path
package.loaded['scripts.alerts']={intercept=function() end}
package.loaded['scripts.audio']={play=function() end}
local function render() local r={valid=true};r.destroy=function() r.valid=false end;return r end
rendering={draw_sprite=render,draw_light=render}
local surface={create_trivial_smoke=function() end,create_entity=function() end}
game={tick=0,get_surface=function() return surface end,forces={[1]={}}}
local missile={id=1,position={x=1000,y=0},force_index=1}
local current={projectiles={},active_missiles={[1]=missile},counters={intercepted=0},rng_state=1234}
storage={shahed_attack={surfaces={[1]=current}}}
local ordnance=require('scripts.ordnance')
local shot=ordnance.launch_interceptor(current,{position={x=0,y=.8},force={index=1},surface=surface},missile,0)
game.tick=shot.flight_tick;ordnance.update(game.tick)
local speeds={}
for elapsed=1,18 do
 game.tick=shot.flight_tick+elapsed
 local before={x=shot.position.x,y=shot.position.y};ordnance.update(game.tick)
 local dx,dy=shot.position.x-before.x,shot.position.y-before.y
 speeds[elapsed]=math.sqrt(dx*dx+dy*dy)
 if elapsed>1 then assert(speeds[elapsed]>=speeds[elapsed-1]-.00001,'Missile accelerates monotonically') end
end
assert(speeds[1]<0.8,'Initial motion should be gentler than the previous 0.95 tiles/tick')
assert(speeds[8]<3.2,'The first eight ticks should retain a visibly slower launch phase')
assert(math.abs(speeds[18]-6)<.00001,'Keep the original cruise speed')
print('PASS: slower initial motion, progressive acceleration, unchanged cruise speed')
