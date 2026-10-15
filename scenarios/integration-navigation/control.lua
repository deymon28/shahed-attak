local target
local decoy
local drone
local initial_distance

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function distance(left, right)
  local dx = left.x - right.x
  local dy = left.y - right.y
  return math.sqrt(dx * dx + dy * dy)
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
  decoy = surface.create_entity({name = "character", position = {25, 0}, force = game.forces.player})
  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={0,-30},force="enemy",raise_built=true})
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger=false,
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    origin_position = {x = 0, y = -30},
    size = 2
  })
  if not result.ok then
    fail("could not create navigation-test raid")
  end
  local drones = surface.find_entities_filtered({
    name = {"shahed-attack-strike-drone", "shahed-attack-heavy-drone"}
  })
  drone = drones[1]
  if not drone then
    fail("navigation-test drone was not found")
  end
  initial_distance = distance(drone.position, target.position)
  if initial_distance > 36 then
    fail("requested raid origin was ignored")
  end
end)

script.on_nth_tick(60, function(event)
  if event.tick == 180 then
    if not drone.valid then
      fail("strike drone reached the factory implausibly quickly")
    end
    if distance(drone.position, target.position) >= initial_distance - 3 then
      fail("strike drone is not approaching the production building")
    end
    if distance(drone.position, decoy.position) < distance(drone.position, target.position) then
      fail("strike drone diverted toward the player character")
    end
  elseif event.tick == 720 then
    -- Two 140-damage strike warheads may leave a 300 HP assembler barely
    -- alive (fire decides), so a direct hit is checked, not destruction.
    local state = remote.call("shahed_attack", "get_surface_state", 1)
    if state.counters.drone_impacts < 1
      or (target.valid and target.health > target.max_health - 140) then
      fail(string.format("strike drone did not reach and attack the production building: health=%s impacts=%d",
        target.valid and string.format("%.1f", target.health) or "destroyed", state.counters.drone_impacts))
    end
    if not decoy.valid then
      fail("strike drone attacked the player character")
    end
    log("SHAHED_TEST_PASS slow strike drone ignored the character and attacked production")
  end
end)
