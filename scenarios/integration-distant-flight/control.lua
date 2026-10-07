local surface, radar, target, event_id, warning_tick, warning_eta
local function check(value,message) if not value then error("SHAHED_TEST_FAIL: "..message) end end
script.on_init(function()
  game.speed=1000
  -- The air war is fought on Nauvis only; chunks beyond the start area are
  -- generated without enemies and the flight gap stays ungenerated.
  surface=game.surfaces[1]
  local settings=surface.map_gen_settings
  settings.water=0
  settings.autoplace_controls=settings.autoplace_controls or {}
  settings.autoplace_controls["enemy-base"]={frequency=0,size=0,richness=0}
  surface.map_gen_settings=settings
  surface.always_day=true
  surface.request_to_generate_chunks({0,0},2)
  surface.request_to_generate_chunks({-1400,0},2)
  surface.force_generate_chunk_requests()
  check(not surface.is_chunk_generated({-22,0}),"flight gap starts ungenerated")
  target=surface.create_entity({name="assembling-machine-1",position={0,0},force="player",raise_built=true})
  target.destructible=false
  radar=surface.create_entity({name="shahed-attack-early-warning-radar",position={0,8},force="player",raise_built=true})
  radar.destructible=false
  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={-1400,0},force="enemy",raise_built=true})
  local result=remote.call("shahed_attack","schedule_event",{kind="raid", stagger=false,surface_index=surface.index,
    target_position=target.position,origin_position={x=-1400,y=0},size=2})
  check(result.ok,"launch distant flight fixture")
  event_id=result.event_id
end)
script.on_event(defines.events.on_tick,function(event)
  radar.energy=10000000
  if event.tick%60~=0 then return end
  local current=remote.call("shahed_attack","get_surface_state",surface.index)
  for _,warning in ipairs(current.warnings) do
    if warning.id==event_id and not warning_tick then
      warning_tick=warning.tick;warning_eta=warning.eta
      check(warning.eta>=30 and warning.eta<=60,"distant drone warning lead time")
      check(warning.direction=="west","distant incoming bearing")
      check(warning.tick>6000,"no immediate warning for a 1400-tile launch")
    end
  end
  if current.active_drones==0 and event.tick>60 then
    check(warning_tick,"distant flight reaches radar coverage")
    check(event.tick-warning_tick>=30*60 and event.tick-warning_tick<=70*60,"actual flight after warning remains a useful reaction interval")
    check((current.audio_counters["shahed-attack-drone-impact"] or 0)>0,"distant drones reach the factory across the ungenerated gap")
    log("SHAHED_TEST_PASS 1400-tile flight crosses disconnected generated regions, warns late in travel, and reaches the target")
    script.on_event(defines.events.on_tick,nil)
  end
  if event.tick>60000 then error("SHAHED_TEST_FAIL: distant flight stalled "..helpers.table_to_json(current)) end
end)
