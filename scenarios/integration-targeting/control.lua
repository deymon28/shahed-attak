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
  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={-200,0},force="enemy",raise_built=true})
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger=false, origin_position={x=-200,y=0},
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
