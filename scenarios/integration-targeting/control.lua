local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local decoy = surface.create_entity({name = "character", position = {0, 0}, force = game.forces.player})
  if not decoy then
    fail("could not create character decoy")
  end
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = decoy.position,
    size = 2
  })
  if result.ok then
    fail("air raid accepted a character instead of requiring a production target")
  end
  log("SHAHED_TEST_PASS character was rejected as an air-raid target")
end)
