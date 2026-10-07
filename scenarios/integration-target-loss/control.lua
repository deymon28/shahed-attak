local target

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function drone_count(surface)
  return #surface.find_entities_filtered({
    name = {
      "shahed-attack-recon-drone",
      "shahed-attack-strike-drone",
      "shahed-attack-heavy-drone"
    }
  })
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  if not target then
    fail("could not create the only production target")
  end

  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={0,-160},force="enemy",raise_built=true})
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger=false,
    surface_index = surface.index,
    target_force_name = "player",
    target_position = {0, 0},
    origin_position = {x = 0, y = -160},
    size = 8
  })
  if not result or not result.ok or drone_count(surface) ~= 8 then
    fail("could not create eight-drone target-loss raid")
  end
end)

script.on_event(defines.events.on_tick, function(event)
  local surface = game.surfaces[1]
  if event.tick == 61 then
    if not target or not target.valid then
      fail("production target disappeared before the diagnostic step")
    end
    target.destroy({raise_destroy = true})
  elseif event.tick == 121 then
    local remaining = drone_count(surface)
    if remaining ~= 8 then
      fail(string.format(
        "surviving raid vanished after its shared target was destroyed: expected=8 actual=%d",
        remaining
      ))
    end
    log("SHAHED_TEST_PASS surviving raid keeps flying after its selected target is destroyed")
  end
end)
