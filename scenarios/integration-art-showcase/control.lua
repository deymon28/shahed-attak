local surface, radar, battery, target, source, aa
local function create(name, position, force)
  local entity=surface.create_entity({name=name,position=position,force=force or "player",raise_built=true})
  assert(entity, "Could not create showcase entity " .. name)
  entity.destructible=false
  return entity
end

script.on_init(function()
  surface=game.surfaces[1]
  surface.always_day=true
  surface.request_to_generate_chunks({0,0},4)
  surface.force_generate_chunk_requests()
  for _,entity in ipairs(surface.find_entities_filtered({area={{-30,-30},{30,30}},type={"tree","simple-entity","cliff"}})) do entity.destroy() end
  local tiles={}
  for x=-24,24 do for y=-18,18 do tiles[#tiles+1]={name="refined-concrete",position={x,y}} end end
  surface.set_tiles(tiles)
  radar=create("shahed-attack-early-warning-radar",{-5,-2})
  aa=create("shahed-attack-aa-turret",{0,-2})
  aa.insert({name="shahed-attack-flak-magazine",count=100})
  battery=create("shahed-attack-abm-battery",{5,-2})
  battery.insert({name="shahed-attack-interceptor",count=100})
  create("gun-turret",{-5,5})
  create("laser-turret",{0,5})
  create("assembling-machine-2",{5,5})
  create("shahed-attack-airfield",{-10,-10},"enemy")
  source=create("shahed-attack-ballistic-site",{10,-10},"enemy")
  target=create("assembling-machine-1",{16,6})
  for i,name in ipairs({"recon","strike","heavy"}) do
    local drone=create("shahed-attack-"..name.."-drone",{i*5-10,-7},"enemy")
    drone.orientation=i/8
    drone.commandable.set_command({type=defines.command.stop,distraction=defines.distraction.none})
  end
  remote.call("shahed_attack","set_intercept_accuracy",0)
end)

script.on_event(defines.events.on_tick,function(event)
  radar.energy=10000000
  battery.energy=20000000
  if event.tick==30 then
    remote.call("shahed_attack","schedule_event",{kind="ballistic",target_position=target.position,source_position=source.position})
  end
  if event.tick==40 or event.tick==100 or event.tick==180 then
    game.take_screenshot({surface=surface,position={2,-3},resolution={1600,1000},zoom=1.25,
      path="air-war-showcase-"..event.tick..".png",show_entity_info=false})
  end
  if event.tick==220 then
    surface.always_day=false;surface.freeze_daytime=true;surface.daytime=0.45
  end
  if event.tick==260 then
    game.take_screenshot({surface=surface,position={2,-3},resolution={1600,1000},zoom=1.25,
      path="air-war-showcase-night.png",show_entity_info=false})
  end
  if event.tick==360 then
    log("SHAHED_TEST_PASS graphical day/night showcase and animated weapon effects")
    script.on_event(defines.events.on_tick,nil)
  end
end)
