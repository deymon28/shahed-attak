local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  for index = 1, 16 do
    local entity = surface.create_entity({
      name = "assembling-machine-1",
      position = {(index % 4) * 10, math.floor(index / 4) * 10},
      force = game.forces.player,
      raise_built = true
    })
    if not entity then
      fail("could not create production target")
    end
  end

  -- The maximum raid size is a map setting (default 40); verify it is enforced.
  assert(remote.call("shahed_attack", "set_setting", "shahed-attack-max-raid-size", 12).ok, "SHAHED_TEST_FAIL: set raid cap")
  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={0,-200},force="enemy",raise_built=true})
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger=false,
    surface_index = 1,
    target_force_name = "player",
    target_position = {10, 0},
    origin_position = {x = 0, y = -200},
    size = 24
  })
  if not result or not result.ok then
    fail("could not schedule oversized raid")
  end
end)

script.on_nth_tick(60, function(event)
  if event.tick ~= 60 then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  local count = current.active_drones
  if count ~= 12 then
    fail(string.format("raid hard cap was not enforced: expected=12 actual=%d", count))
  end
  log("SHAHED_TEST_PASS raid entry points enforce the configured maximum raid size")
end)
