local target
local outer_target
local outer_initial_health

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
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
  outer_target = surface.create_entity({
    name = "storage-tank",
    position = {8, 0},
    force = game.forces.player,
    raise_built = true
  })
  outer_initial_health = outer_target.health
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    origin_position = {x = 0, y = -14},
    size = 2
  })
  if not result.ok then
    fail("could not create drone impact test")
  end
end)

script.on_nth_tick(60, function(event)
  if event.tick ~= 480 then
    return
  end
  if target.valid then
    fail("strike drones did not destroy their production target")
  end
  if not outer_target.valid or outer_target.health >= outer_initial_health then
    fail("strike blast has no readable outer damage zone")
  end
  local scorchmarks = game.surfaces[1].find_entities_filtered({
    name = {"medium-scorchmark", "big-scorchmark"},
    position = {0, 0},
    radius = 5
  })
  if #scorchmarks == 0 then
    fail("strike impact left no persistent visible crater")
  end
  log("SHAHED_TEST_PASS drone impact has visible crater and layered blast damage")
end)
