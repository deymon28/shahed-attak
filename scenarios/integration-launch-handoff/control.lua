local surface
local function check_body(expected)
  local bodies = 0
  for _, object in pairs(rendering.get_all_objects("shahed-attack")) do
    if object.valid and object.type == "sprite"
      and object.sprite == "shahed-attack-ballistic-missile-sprite" then
      bodies = bodies + 1
      assert(object.visible == expected, "SHAHED_TEST_FAIL: duplicate or missing flight body at launch handoff")
    end
  end
  assert(bodies == 2, "SHAHED_TEST_FAIL: expected flight body and shadow")
end

script.on_init(function()
  game.speed = 16
  surface = game.surfaces[1]
  local target = surface.create_entity({name="assembling-machine-1",position={0,0},force="player",raise_built=true})
  local site = surface.create_entity({name="shahed-attack-ballistic-site",position={-320,0},force="enemy",raise_built=true})
  assert(target and site, "SHAHED_TEST_FAIL: could not create launch fixture")
  local result = remote.call("shahed_attack", "schedule_event", {
    kind="ballistic", surface_index=surface.index, target_force_name="player",
    target_position=target.position, source_position=site.position
  })
  assert(result.ok, "SHAHED_TEST_FAIL: could not launch fixture missile")
end)

script.on_event(defines.events.on_tick, function(event)
  if event.tick == 10 then
    check_body(false)
    local state = remote.call("shahed_attack", "get_surface_state", surface.index)
    assert(state.visuals.idle == 0, "SHAHED_TEST_FAIL: idle hatch visible during launch")
  elseif event.tick == 70 then
    check_body(true)
  elseif event.tick == 90 then
    local state = remote.call("shahed_attack", "get_surface_state", surface.index)
    assert(state.visuals.idle == 1, "SHAHED_TEST_FAIL: hatch did not return after handoff")
    log("SHAHED_TEST_PASS launch body handoff and hatch closure")
    script.on_event(defines.events.on_tick, nil)
  end
end)
