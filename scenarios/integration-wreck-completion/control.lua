local surface
local target
local first_batch = {}
local second_batch = {}
local starting_outcomes = 0

local wreck_names = {}
for _, outcome in ipairs({"safe", "fuel", "warhead"}) do
  for direction = 0, 7 do
    wreck_names[#wreck_names + 1] = "shahed-attack-falling-recon-wreck-" .. outcome .. "-" .. direction
  end
end

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function outcome_total()
  local counters = remote.call("shahed_attack", "get_surface_state", surface.index).counters
  return (counters.wreck_safe or 0) + (counters.wreck_fuel or 0) + (counters.wreck_warhead or 0)
end

local function nearest_new_drone(origin, seen)
  local nearest
  local best
  for _, drone in ipairs(surface.find_entities_filtered({name = "shahed-attack-recon-drone"})) do
    if drone.valid and not seen[drone.unit_number] then
      local dx = drone.position.x - origin.x
      local dy = drone.position.y - origin.y
      local distance = dx * dx + dy * dy
      if not best or distance < best then
        nearest, best = drone, distance
      end
    end
  end
  return nearest
end

local function spawn_batch(count, radius)
  local result = {}
  local seen = {}
  for _, drone in ipairs(surface.find_entities_filtered({name = "shahed-attack-recon-drone"})) do
    if drone.valid then seen[drone.unit_number] = true end
  end
  for index = 0, count - 1 do
    local direction = index % 8
    local angle = -math.pi / 2 + direction * math.pi / 4
    local motion = {x = math.cos(angle), y = math.sin(angle)}
    local ring = radius + math.floor(index / 8) * 4
    local origin = {x = -motion.x * ring, y = -motion.y * ring}
    local scheduled = remote.call("shahed_attack", "schedule_event", {
      kind = "recon",
      surface_index = surface.index,
      target_force_name = "player",
      target_position = target.position,
      origin_position = origin,
      size = 1
    })
    if not scheduled.ok then fail("could not schedule wreck test drone") end
    local drone = nearest_new_drone(origin, seen)
    if not drone then fail("could not identify wreck test drone") end
    seen[drone.unit_number] = true
    result[#result + 1] = {entity = drone, motion = motion}
  end
  return result
end

local function kill_batch(batch)
  for _, record in ipairs(batch) do
    local drone = record.entity
    if not drone.valid then fail("test drone disappeared before controlled death") end
    drone.die(game.forces.player)
  end
end

local function steer_batch(batch)
  for _, record in ipairs(batch) do
    if not record.entity.valid then fail("test drone disappeared before direction sample") end
    record.entity.teleport({
      x = record.entity.position.x + record.motion.x * 20,
      y = record.entity.position.y + record.motion.y * 20
    })
  end
end

local function active_wrecks()
  return surface.find_entities_filtered({name = wreck_names})
end

script.on_init(function()
  game.speed = 16
  surface = game.surfaces[1]
  target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  if not target then fail("could not create wreck test target") end
  first_batch = spawn_batch(8, 44)
  starting_outcomes = outcome_total()
end)

script.on_nth_tick(1, function(event)
  if event.tick == 179 then
    steer_batch(first_batch)
  elseif event.tick == 181 then
    kill_batch(first_batch)
  elseif event.tick == 182 then
    local wrecks = active_wrecks()
    if #wrecks ~= 8 then fail("eight deaths did not create eight wrecks") end
    local directions = {}
    for _, wreck in ipairs(wrecks) do
      local direction = tonumber(wreck.name:match("%-(%d)$"))
      directions[direction] = true
    end
    for direction = 0, 7 do
      if not directions[direction] then fail("directional wreck sector is missing") end
    end
  elseif event.tick == 302 then
    if #active_wrecks() ~= 0 then fail("first wreck batch did not finish") end
    if outcome_total() ~= starting_outcomes + 8 then fail("first wreck batch did not complete exactly once") end
    if remote.call("shahed_attack", "get_surface_state", surface.index).active_drones ~= 0 then
      fail("first wreck batch left tracked drones")
    end
    second_batch = spawn_batch(24, 48)
  elseif event.tick == 479 then
    steer_batch(second_batch)
  elseif event.tick == 481 then
    kill_batch(second_batch)
  elseif event.tick == 602 then
    if #active_wrecks() ~= 0 then fail("stress wreck batch did not finish") end
    if outcome_total() ~= starting_outcomes + 32 then fail("stress batch double-completed or missed an outcome") end
    if remote.call("shahed_attack", "get_surface_state", surface.index).active_drones ~= 0 then
      fail("stress wreck batch left tracked drones")
    end
    log("SHAHED_TEST_PASS 32 directional wrecks complete once with no leaked projectiles")
  end
end)
