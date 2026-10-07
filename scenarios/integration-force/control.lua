local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    size = 2
  })
  if not result.ok then
    fail("could not create force-test raid")
  end
  local drones = surface.find_entities_filtered({
    name = {"shahed-attack-strike-drone", "shahed-attack-heavy-drone"}
  })
  if not drones[1] then
    fail("force-test drone was not found")
  end
  if drones[1].force.name ~= "shahed-attack-enemy" then
    fail("air drone still belongs to the vanilla biter force")
  end
  if not drones[1].force.get_friend("enemy") or not game.forces.enemy.get_friend(drones[1].force) then
    fail("air force and biter force are not allied")
  end
  log("SHAHED_TEST_PASS air branch uses an allied but separate force")
end)
