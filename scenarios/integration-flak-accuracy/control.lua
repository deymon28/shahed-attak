local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local turret = surface.create_entity({
    name = "shahed-attack-aa-turret",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  if not turret or turret.insert({name = "shahed-attack-flak-magazine", count = 100}) == 0 then
    fail("could not arm accuracy-test turret")
  end
  local drone = surface.create_entity({
    name = "shahed-attack-heavy-drone",
    position = {20, 0},
    force = game.forces["shahed-attack-enemy"]
  })
  if not drone then
    fail("could not create accuracy-test drone")
  end
  drone.commandable.set_command({
    type = defines.command.stop,
    distraction = defines.distraction.none
  })
end)

script.on_nth_tick(60, function(event)
  if event.tick ~= 600 then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  local shots = current.counters.flak_shots or 0
  local hits = current.counters.flak_hits or 0
  local misses = current.counters.flak_misses or 0
  if shots < 5 or hits == 0 then
    fail("flak turret did not register actual shots and hits")
  end
  if misses < 2 then
    fail("flak turret remained perfectly accurate")
  end
  log(string.format(
    "SHAHED_TEST_PASS flak turret visibly misses shots: shots=%d hits=%d misses=%d",
    shots,
    hits,
    misses
  ))
end)
