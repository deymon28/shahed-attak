local surface
local drone
local wreck_seen = false
local starting_drones = 0
local starting_outcomes = 0

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  surface = game.surfaces[1]
  local target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  if not target then
    fail("could not create crash-test target")
  end
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    size = 2
  })
  if not result.ok then
    fail("could not create tracked drone")
  end
  local drones = surface.find_entities_filtered({
    name = {"shahed-attack-strike-drone", "shahed-attack-heavy-drone"}
  })
  if not drones[1] then
    fail("tracked drone was not found")
  end
  drone = drones[1]
  local status = remote.call("shahed_attack", "get_surface_state", surface.index)
  starting_drones = status.active_drones
  starting_outcomes = (status.counters.wreck_safe or 0)
    + (status.counters.wreck_fuel or 0)
    + (status.counters.wreck_warhead or 0)
end)

local wreck_names = {}
for _, outcome in ipairs({"safe", "fuel", "warhead"}) do
  for direction = 0, 7 do
    wreck_names[#wreck_names + 1] = "shahed-attack-falling-wreck-" .. outcome .. "-" .. direction
  end
end

script.on_nth_tick(1, function()
  if game.tick == 1 and drone and drone.valid then
    drone.die(game.forces.player)
    return
  end
  if game.tick == 2 then
    local wrecks = surface.find_entities_filtered({name = wreck_names})
    if #wrecks == 0 then
      fail("tracked drone death did not create a falling wreck")
    end
    wreck_seen = true
    local status = remote.call("shahed_attack", "get_surface_state", surface.index)
    if status.active_drones ~= starting_drones - 1 then
      fail("one drone death removed unrelated raid members")
    end
  elseif game.tick == 121 then
    if not wreck_seen then
      fail("falling wreck was never observed")
    end
    local wrecks = surface.find_entities_filtered({name = wreck_names})
    if #wrecks > 0 then
      fail("falling wreck flew indefinitely instead of hitting the ground")
    end
    local status = remote.call("shahed_attack", "get_surface_state", surface.index)
    local completed = (status.counters.wreck_safe or 0)
      + (status.counters.wreck_fuel or 0)
      + (status.counters.wreck_warhead or 0)
    if completed ~= starting_outcomes + 1 then
      fail("wreck outcome did not complete exactly once")
    end
    if status.active_drones ~= starting_drones - 1 then
      fail("unrelated drone disappeared while wreck completed")
    end
    log("SHAHED_TEST_PASS one drone creates one finite directional wreck without removing its raid")
  end
end)
