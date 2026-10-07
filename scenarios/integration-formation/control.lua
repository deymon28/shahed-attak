local drones = {}

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function distance(left, right)
  local dx = left.x - right.x
  local dy = left.y - right.y
  return math.sqrt(dx * dx + dy * dy)
end

local function minimum_spacing(entities)
  local result = math.huge
  local closest_left
  local closest_right
  for left = 1, #entities do
    for right = left + 1, #entities do
      if entities[left].valid and entities[right].valid then
        local current = distance(entities[left].position, entities[right].position)
        if current < result then
          result = current
          closest_left = entities[left]
          closest_right = entities[right]
        end
      end
    end
  end
  return result, closest_left, closest_right
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local positions = {
    {0, 0}, {-20, 0}, {20, 0},
    {0, 20}, {-20, 20}, {20, 20}
  }
  for _, position in ipairs(positions) do
    surface.create_entity({
      name = "assembling-machine-1",
      position = position,
      force = game.forces.player,
      raise_built = true
    })
  end
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = {0, 0},
    origin_position = {x = 0, y = -120},
    size = 6
  })
  if not result.ok then
    fail("could not create formation test raid")
  end
  drones = surface.find_entities_filtered({
    name = {"shahed-attack-strike-drone", "shahed-attack-heavy-drone"}
  })
  if #drones ~= 6 then
    fail("formation test did not create six drones")
  end
  if minimum_spacing(drones) < 8 then
    fail("drones spawned in an overlapping cluster")
  end
  local destinations = {}
  for _, drone in ipairs(drones) do
    local command = drone.commandable and drone.commandable.command
    local destination = command and command.destination
    if destination then
      local key = string.format("%.1f:%.1f", destination.x, destination.y)
      destinations[key] = true
    end
  end
  local destination_count = 0
  for _ in pairs(destinations) do destination_count = destination_count + 1 end
  if destination_count < 3 then
    fail("raid drones were all assigned to the same production building")
  end
end)

script.on_nth_tick(60, function(event)
  if event.tick ~= 360 then
    return
  end
  local spacing, left, right = minimum_spacing(drones)
  if spacing < 5 then
    fail(string.format(
      "drones converged into an unreadable in-flight cluster: spacing=%.2f left=%d@(%.2f,%.2f) right=%d@(%.2f,%.2f)",
      spacing,
      left.unit_number,
      left.position.x,
      left.position.y,
      right.unit_number,
      right.position.x,
      right.position.y
    ))
  end
  log("SHAHED_TEST_PASS raid keeps a loose multi-target formation")
end)
