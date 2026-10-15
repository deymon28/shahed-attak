-- Scenario code runs before the mod's on_init. Remote attacks without a
-- source hint must still find the bases the scenario has just placed.
local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local target = surface.create_entity({name = "assembling-machine-1", position = {0, 0}, force = "player",
    raise_built = true})
  local airfield = surface.create_entity({name = "shahed-attack-airfield", position = {-200, 0}, force = "enemy",
    raise_built = true})
  local site = surface.create_entity({name = "shahed-attack-ballistic-site", position = {600, 0}, force = "enemy",
    raise_built = true})
  if not target or not airfield or not site then
    fail("could not create scenario entities")
  end
  local raid = remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger = false, target_force_name = "player", target_position = target.position, size = 2
  })
  local ballistic = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic", target_force_name = "player", target_position = target.position
  })
  if not raid.ok or not ballistic.ok then
    fail("remote attacks without a source hint failed: raid=" .. tostring(raid.error)
      .. " ballistic=" .. tostring(ballistic.error))
  end
  local state = remote.call("shahed_attack", "get_surface_state", 1)
  if state.active_drones < 1 or state.active_missiles ~= 1 then
    fail("attacks were not launched")
  end
  if state.missiles[1].source_unit_number ~= site.unit_number then
    fail("missile did not start at the placed launch site")
  end
  for _, drone in ipairs(state.drones) do
    if drone.source_unit_number ~= airfield.unit_number then
      fail("drone did not start at the placed airfield")
    end
  end
  log("SHAHED_TEST_PASS remote attacks before the mod's on_init start at the placed bases")
end)
