local surface, flame, laser, gun, ground, tree
local drones = {}
local burning_tree_seen, laser_ground_hit, gun_ground_hit
local laser_target, gun_target
local function check(value,message) if not value then error("SHAHED_TEST_FAIL: "..message) end end
local function drone(position)
  local entity=surface.create_entity({name="shahed-attack-heavy-drone",position=position,force="enemy"})
  entity.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
  drones[#drones+1]=entity
  return entity
end
script.on_init(function()
  game.speed=16
  surface=game.surfaces[1]
  -- The scenario map seed varies: keep natural biters away from the turrets.
  surface.peaceful_mode=true
  surface.request_to_generate_chunks({80,0},6)
  surface.force_generate_chunk_requests()
  for _,entity in ipairs(surface.find_entities_filtered({area={{-64,-64},{224,64}},force="enemy"})) do entity.destroy() end
  flame=surface.create_entity({name="flamethrower-turret",position={0,0},direction=defines.direction.east,force="player"})
  ground=surface.create_entity({name="behemoth-biter",position={18,0},force="enemy"})

  ground.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
  tree=surface.create_entity({name="tree-01",position={18,0}})

  drone({18,0})
  laser=surface.create_entity({name="laser-turret",position={80,0},force="player"})
  drone({80,-8})
  gun=surface.create_entity({name="gun-turret",position={160,0},force="player"})
  gun.insert({name="uranium-rounds-magazine",count=100})
  drone({160,-8})
end)
script.on_event(defines.events.on_tick,function(event)
  if ground.valid then ground.health=3000 end
  if tree.valid then tree.health=50 end
  flame.fluidbox[1]={name="crude-oil",amount=100}
  laser.energy=10000000
  if surface.count_entities_filtered({name="shahed-attack-ground-fire-flame-on-tree"})>0 then burning_tree_seen=true end
  if event.tick==600 then
    check(burning_tree_seen,"stationary flamethrower must ignite an actual tree")
    for _,entity in ipairs(drones) do check(entity.valid and entity.health==entity.max_health,"vanilla gun/laser/flame/tree fire cannot damage drones") end
    check(gun.get_inventory(defines.inventory.turret_ammo).get_item_count("uranium-rounds-magazine")==100,"vanilla gun ignores drones")
    laser_target=surface.create_entity({name="big-biter",position={80,-8},force="enemy"})
    gun_target=surface.create_entity({name="big-biter",position={160,-8},force="enemy"})
    laser_target.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
    gun_target.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
  end
  if event.tick>600 then
    if not laser_target.valid or laser_target.health<375 then laser_ground_hit=true end
    if not gun_target.valid or gun_target.health<375 then gun_ground_hit=true end
  end
  if event.tick==900 then
    check(laser_ground_hit and gun_ground_hit,"vanilla turrets still damage ground enemies")
    for _,entity in ipairs(drones) do check(entity.valid and entity.health==entity.max_health,"nearby ground combat still spares drones") end
    log("SHAHED_TEST_PASS vanilla target exclusion, flamethrower tree-fire immunity, and normal ground combat")
    script.on_event(defines.events.on_tick,nil)
  end
end)
