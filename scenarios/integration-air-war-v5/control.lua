local batteries={}
local target,radar,source,drone,turret,player,player_drone
local first_launches,shot_tick,projectile_seen,warning_checked
local function fail(message) error('SHAHED_TEST_FAIL: '..message) end
local function check(value,message) if not value then fail(message) end end

script.on_init(function()
  game.speed=8
  local surface=game.surfaces[1]
  surface.always_day=true
  target=surface.create_entity({name='assembling-machine-1',position={0,0},force='player',raise_built=true})
  radar=surface.create_entity({name='shahed-attack-early-warning-radar',position={0,8},force='player',raise_built=true})
  source=surface.create_entity({name='shahed-attack-ballistic-site',position={-100,0},force='enemy',raise_built=true})
  for i=1,5 do
    local battery=surface.create_entity({name='shahed-attack-abm-battery',position={i*4-12,-12},force='player',raise_built=true})
    check(battery,'create battery')
    battery.insert({name='shahed-attack-interceptor',count=100})
    batteries[i]=battery
  end
  remote.call('shahed_attack','set_intercept_accuracy',0)
  drone=surface.create_entity({name='shahed-attack-heavy-drone',position={500,-8},force='enemy'})
  drone.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
  turret=surface.create_entity({name='gun-turret',position={500,0},force='player'})
  turret.insert({name='uranium-rounds-magazine',count=100})
  surface.create_entity({name='shahed-attack-ground-fire-flame',position=drone.position,force='player'})
  player=surface.create_entity({name='character',position={600,0},force='player'})
  player_drone=surface.create_entity({name='shahed-attack-strike-drone',position={600,-8},force='enemy'})
  player_drone.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
end)

script.on_event(defines.events.on_tick,function(event)
  local tick=event.tick
  radar.energy=10000000
  for _,battery in ipairs(batteries) do battery.energy=20000000 end
  if player_drone.valid then
    if tick==60 then
      local ammo=prototypes.item['uranium-rounds-magazine'].get_ammo_type('player')
      local physical=false
      local function inspect(node)
        if type(node)~='table' then return end
        if node.amount and node.type=='physical' then physical=true end
        check(not (type(node.type)=='string' and node.type:find('shahed%-attack%-ground')),'player ammo has no turret damage')
        for _,child in pairs(node) do if type(child)=='table' then inspect(child) end end
      end
      inspect(ammo)
      check(physical,'player ammo retains physical damage')
      player_drone.damage(24,game.forces.player,'physical',player)
    end
  end
  if tick==5 then
    local result=remote.call('shahed_attack','schedule_event',{kind='ballistic',target_position=target.position,source_position=source.position})
    check(result.ok,'schedule missile at real launch site')
  end
  if tick>5 then
    local current=remote.call('shahed_attack','get_surface_state',1)
    if #current.projectiles>0 then projectile_seen=true end
    local count=current.counters.interceptor_launches or 0
    if not shot_tick and count>0 then
      shot_tick=tick;first_launches=count
      check(tick>=13,'ready batteries aim briefly before firing')
      check(current.active_missiles==1,'launch does not resolve interception instantly')
    end
    -- Fire doctrine: at most two interceptors fly at one target; misses free a slot.
    if tick==35 then check(count==2,'two batteries engage while the others hold fire') end
    if tick==35 then first_launches=count end
    if tick==95 then check(count>first_launches,'batteries fire again after interceptors miss') end
    if tick>13 and tick<140 then
      local in_flight=0
      for _,shot in ipairs(current.projectiles) do if not shot.missed then in_flight=in_flight+1 end end
      check(in_flight<=2,'never more than two interceptors in flight at one missile')
    end
    if not warning_checked and #current.warnings>0 then
      local warning=current.warnings[1]
      check(warning.eta>=30 and warning.eta<=60,'warning leaves 30-60 seconds')
      check(warning.direction=='west','incoming bearing from western launch site')
      warning_checked=true
    end
    if tick==140 then remote.call('shahed_attack','set_intercept_accuracy',1) end
    if tick==300 then
      check(projectile_seen,'visible interceptor lifecycle exposed')
      check(warning_checked,'early warning sent')
      check(current.counters.intercepted==1,'missile destroyed exactly once')
      check(current.active_missiles==0,'destroyed missile cleaned')
      check(#current.projectiles==0,'all in-flight helpers cleaned')
      check(drone.valid and drone.health==drone.max_health,'vanilla gun and turret ground fire cannot damage drone')
      check(turret.get_inventory(defines.inventory.turret_ammo).get_item_count('uranium-rounds-magazine')==100,'vanilla turret does not waste ammunition')
      check(not player_drone.valid or player_drone.health<player_drone.max_health,'ordinary player damage reaches the drone')
      first_launches=count
    end
    if tick==420 then
      check(count==first_launches,'no firing after interception')
      log('SHAHED_TEST_PASS v5 player damage compatibility, vanilla immunity, early bearing, fire doctrine and projectile cleanup')
    end
  end
end)
