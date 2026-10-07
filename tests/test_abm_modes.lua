package.path = './?.lua;' .. package.path
package.loaded['scripts.alerts'] = {intercept=function() end}
package.loaded['scripts.audio'] = {play=function() end}
package.loaded['scripts.visual_effects'] = {play_abm_launch=function() end}
local function render()
  local object = {valid=true}
  object.destroy = function() object.valid=false end
  return object
end
rendering = {draw_sprite=render, draw_light=render}
defines = {inventory={turret_ammo=1}, entity_status_diode={green=1,yellow=2,red=3}}
settings = {global={['shahed-attack-intercept-accuracy']={value=1}}}
local world = {index=1, create_entity=function() end, create_trivial_smoke=function() end}
local force = {index=1, get_friend=function() return false end, get_cease_fire=function() return false end}
game = {tick=0, forces={[1]=force}, get_surface=function() return world end}
local defense = require('scripts.defense')
local ordnance = require('scripts.ordnance')
local current
local function fixture(mode)
  current = {defenses={abm_batteries={}},active_missiles={},active_drones={},projectiles={},
    counters={intercepted=0},rng_state=1234,battery_modes=mode and {[1]=mode} or nil}
  storage = {shahed_attack={surfaces={[1]=current}}}
  game.tick=0
  local inventory={count=10}
  inventory.get_item_count=function() return inventory.count end
  inventory.remove=function() inventory.count=inventory.count-1; return 1 end
  local battery={valid=true,name='shahed-attack-abm-battery',unit_number=1,surface=world,
    force=force,position={x=0,y=0},orientation=0,energy=100000000,get_inventory=function() return inventory end}
  current.defenses.abm_batteries[1]=battery
  return battery,inventory
end
local function missile(id, x)
  local target={id=id,force_index=1,position={x=x or 80,y=0},probabilities={}}
  current.active_missiles[id]=target
  return target
end
local function drone(id, kind, x, target_force)
  local entity={valid=true,unit_number=id,force={index=2},position={x=x or 70,y=0}}
  entity.die=function() entity.valid=false; current.active_drones[id]=nil; return true end
  current.active_drones[id]={entity=entity,kind=kind or 'strike',target_force_index=target_force or 1}
  return entity
end
local function advance(first,last)
  for tick=first,last do
    game.tick=tick
    for _,target in pairs(current.active_missiles) do defense.try_intercepts(target,current) end
    defense.update_drone_intercepts(tick)
    ordnance.update(tick)
  end
end

local battery,inventory=fixture('drones')
local target=missile(1)
for tick=1,30 do game.tick=tick; defense.try_intercepts(target,current) end
assert(inventory.count==10,'Drone-only batteries must ignore ballistic missiles')

battery,inventory=fixture()
local shahed=drone(1)
advance(1,60)
assert(inventory.count==10 and shahed.valid,'Existing batteries default to ballistic-only without consuming drone ammunition')
assert(defense.get_mode(battery)=='ballistic','Missing mode must have a safe default')
target=missile(2)
advance(61,120)
assert(target.intercepted and inventory.count==9,'Default ballistic interception retains its existing behavior')

for _,kind in ipairs({'strike','heavy'}) do
  battery,inventory=fixture('drones')
  shahed=drone(1,kind)
  advance(1,60)
  assert(not shahed.valid and inventory.count==9,'Drone interception must destroy '..kind..' targets with one charged launch')
  assert(battery.energy==90000000,'Drone launch must retain the existing energy cost')
end

battery,inventory=fixture('both')
shahed=drone(1)
target=missile(1)
advance(1,30)
local shot=next(current.projectiles) and select(2,next(current.projectiles))
assert(shot and shot.target_missile_id==1 and not shot.target_drone,'Mixed mode chooses ballistics before drones, even with matching IDs')
advance(31,140)
assert(target.intercepted and not shahed.valid and inventory.count==8,'Mixed mode resumes drone defense after ballistic interception')

battery,inventory=fixture('drones')
shahed=drone(1)
advance(1,24)
assert(inventory.count==9,'Launch drone interceptor before changing mode')
local next_shot=current.battery_next_shot[1]
assert(defense.set_mode(battery,'ballistic'))
assert(current.battery_next_shot[1]==next_shot,'Changing mode must not reset cooldown')
advance(25,65)
assert(not shahed.valid and inventory.count==9,'Already launched interceptors finish after switching mode')
assert(not defense.set_mode(battery,'invalid') and defense.get_mode(battery)=='ballistic','Invalid modes must not change behavior')

battery,inventory=fixture('both')
shahed=drone(1)
advance(1,6)
target=missile(2)
advance(7,30)
shot=select(2,next(current.projectiles))
assert(shot and shot.target_missile_id==2,'An incoming ballistic target preempts unlaunched drone acquisition')

battery,inventory=fixture('drones')
local recon=drone(1,'recon')
local distant=drone(2,'strike',193)
local other=drone(3,'heavy',40,3)
advance(1,60)
assert(inventory.count==10 and recon.valid and distant.valid and other.valid,'Do not expand scope to recon, out-of-range or another force targets')

battery,inventory=fixture('drones')
shahed=drone(1)
advance(1,24)
shahed.valid=false
advance(25,60)
assert(not next(current.projectiles) and inventory.count==9,'Lost drone targets clean up without duplicate charges')

battery,inventory=fixture('drones')
settings.global['shahed-attack-intercept-accuracy'].value=0
shahed=drone(1)
advance(1,70)
assert(shahed.valid and inventory.count==9 and current.counters.interceptor_misses==1,'Drone misses consume one round without a second accuracy roll')
assert(not next(current.projectiles),'Missed drone interceptors expire and clean up')
print('PASS: per-battery modes, safe defaults, target priority, drone hits/misses, mode changes, resource costs and target loss')
