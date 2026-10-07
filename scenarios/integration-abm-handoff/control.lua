local surface, first_launch
local batteries = {}
local offsets = {{-10,-9},{0,-9},{10,-9},{-10,0},{10,0},{-10,9},{0,9},{10,9}}
local headings = {0,.125,.25,.375,.5,.625,.75,.875}
local labels = {"N","NE","E","SE","S","SW","W","NW"}
local captured = {}

script.on_init(function()
  surface = game.surfaces[1]
  surface.always_day = true
  surface.request_to_generate_chunks({0,0}, 6)
  surface.force_generate_chunk_requests()
  for _, entity in ipairs(surface.find_entities_filtered({area={{-22,-18},{22,18}},
    type={"tree","simple-entity","cliff"}})) do entity.destroy() end
  surface.destroy_decoratives({area={{-22,-18},{22,18}}})
  local tiles = {}
  for x=-22,22 do for y=-18,18 do tiles[#tiles+1]={name="refined-concrete", position={x,y}} end end
  surface.set_tiles(tiles)
  for index, heading in ipairs(headings) do
    local force = game.create_force("abm-review-" .. index)
    local x,y = offsets[index][1],offsets[index][2]
    local dx,dy = math.sin(heading*math.pi*2),-math.cos(heading*math.pi*2)
    local battery = surface.create_entity({name="shahed-attack-abm-battery", position={x,y}, force=force, raise_built=true})
    local target = surface.create_entity({name="assembling-machine-1", position={x-dx*24,y-dy*24}, force=force, raise_built=true})
    local site = surface.create_entity({name="shahed-attack-ballistic-site", position={x+dx*128,y+dy*128}, force="enemy", raise_built=true})
    assert(battery and target and site, "SHAHED_TEST_FAIL: create ABM handoff fixture")
    battery.orientation=heading;battery.energy=20000000
    battery.insert({name="shahed-attack-interceptor",count=1})
    batteries[index]=battery
    rendering.draw_text({text=labels[index],surface=surface,target={x=x,y=y+2.6},color={1,1,1},scale=1.5,alignment="center"})
    local result=remote.call("shahed_attack","schedule_event",{kind="ballistic",surface_index=surface.index,
      target_force_name=force.name,target_position=target.position,source_position=site.position})
    assert(result.ok,"SHAHED_TEST_FAIL: schedule directional missile")
  end
  remote.call("shahed_attack","set_intercept_accuracy",0)
end)

script.on_event(defines.events.on_tick,function(event)
  for _,battery in ipairs(batteries) do battery.energy=20000000 end
  local state=remote.call("shahed_attack","get_surface_state",surface.index)
  if not first_launch and #state.projectiles>0 then
    first_launch=state.projectiles[1].start_tick
    log("ABM_HANDOFF first start tick " .. first_launch)
  end
  if first_launch then
    local age=event.tick-first_launch
    if (age==2 or age==8 or age==12 or age==13 or age==14 or age==15 or age==16 or age==20 or age==26) and not captured[age] then
      captured[age]=true
      local visible=0
      for _,object in pairs(rendering.get_all_objects("shahed-attack")) do
        if object.valid and object.type=="sprite" and object.sprite=="shahed-attack-interceptor-sprite" and object.visible then visible=visible+1 end
      end
      log("ABM_HANDOFF age " .. age .. " visible flight bodies " .. visible)
      game.take_screenshot({surface=surface,position={0,0},resolution={1800,1500},zoom=1.65,
        path="abm-handoff-" .. age .. ".png",show_entity_info=false})
    end
  end
  if event.tick==160 then
    assert(state.counters.interceptor_launches==8,"SHAHED_TEST_FAIL: each battery launched once")
    assert(state.counters.interceptor_encounters==8,"SHAHED_TEST_FAIL: every released interceptor reached its target")
    assert(#state.projectiles==0,"SHAHED_TEST_FAIL: all interceptor helpers cleaned up")
    log("SHAHED_TEST_PASS calibrated ABM handoff in eight headings and complete projectile cleanup")
    script.on_event(defines.events.on_tick,nil)
  end
end)
