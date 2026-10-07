local loaded = false
local function check(value,message) if not value then error("SHAHED_TEST_FAIL: "..message) end end
local function launch_objects()
  local body, animation
  for _,object in pairs(rendering.get_all_objects("shahed-attack")) do
    if object.valid and object.type=="sprite" and object.sprite=="shahed-attack-interceptor-sprite" then body=object end
    if object.valid and object.type=="animation" and object.animation:find("shahed-attack-abm-launch-",1,true)==1 then animation=object end
  end
  return body,animation
end
script.on_load(function() loaded=true end)
script.on_init(function()
  local surface=game.surfaces[1]
  surface.always_day=true
  storage.target=surface.create_entity({name="assembling-machine-1",position={0,0},force="player",raise_built=true})
  storage.site=surface.create_entity({name="shahed-attack-ballistic-site",position={-180,0},force="enemy",raise_built=true})
  storage.battery=surface.create_entity({name="shahed-attack-abm-battery",position={0,-8},force="player",raise_built=true})
  storage.initial_ammo=storage.battery.insert({name="shahed-attack-interceptor",count=100})
  storage.battery.energy=20000000
  remote.call("shahed_attack","set_intercept_accuracy",1)
  local result=remote.call("shahed_attack","schedule_event",{kind="ballistic",target_position=storage.target.position,source_position=storage.site.position})
  check(result.ok,"launch reload fixture")
end)
script.on_event(defines.events.on_tick,function(event)
  storage.battery.energy=20000000
  local current=remote.call("shahed_attack","get_surface_state",1)
  if not loaded and event.tick==30 then
    check(#current.projectiles==1 and current.active_missiles==1,"save during actual interceptor flight")
    local body,animation=launch_objects()
    check(body and not body.visible and animation,"save while the launch animation owns the rocket")
    storage.saved_projectile_id=current.projectiles[1].id
    storage.saved_x=current.projectiles[1].position.x
    game.server_save("ordnance-fixture")
  end
  if not loaded and event.tick==31 then log("SHAHED_RELOAD_READY") end
  if loaded and not storage.resume_checked then
    local _,animation=launch_objects()
    check(animation,"the existing launch animation survives save/load")
    check(#current.projectiles==1 and current.projectiles[1].id==storage.saved_projectile_id,"same in-flight projectile survives save/load")
    check(current.projectiles[1].position.x<=storage.saved_x,"projectile resumes forward motion")
    storage.resume_checked=true
  end
  if loaded and event.tick>=120 then
    check(storage.resume_checked,"reload validation ran")
    check(current.active_missiles==0 and #current.projectiles==0,"saved interceptor resolves and cleans up")
    check(current.counters.intercepted==1 and current.counters.interceptor_launches==1,"reload neither rerolls nor duplicates launch/destruction")
    check(storage.battery.get_item_count("shahed-attack-interceptor")==storage.initial_ammo-1,"one ammunition debit across reload")
    log("SHAHED_TEST_PASS active interceptor position, target, outcome, resource cost and cleanup survive a real save/load")
    script.on_event(defines.events.on_tick,nil)
  end
end)
