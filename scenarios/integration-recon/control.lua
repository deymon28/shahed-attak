local recon
local first_orbit_position

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
  local target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  local requested_origin = {x = 0, y = -25}
  game.surfaces[1].create_entity({name="shahed-attack-airfield",position=requested_origin,force="enemy",raise_built=true})
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "recon", stagger=false,
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    origin_position = requested_origin,
    size = 1
  })
  if not result.ok then
    fail("could not create reconnaissance flight")
  end
  local drones = surface.find_entities_filtered({name = "shahed-attack-recon-drone"})
  recon = drones[1]
  if not recon then
    fail("reconnaissance drone was not found")
  end
  if distance(recon.position, requested_origin) > 6 then
    fail("requested reconnaissance origin was ignored")
  end
end)

script.on_nth_tick(60, function(event)
  if not recon or not recon.valid then
    fail("reconnaissance drone disappeared before completing its orbit")
  end
  if event.tick == 360 then
    first_orbit_position = {x = recon.position.x, y = recon.position.y}
  elseif event.tick == 540 then
    if not first_orbit_position then
      fail("first reconnaissance orbit sample is missing")
    end
    if distance(first_orbit_position, recon.position) < 3 then
      fail("reconnaissance drone hovered instead of flying an orbit")
    end
    local radius = distance({x = 0, y = 0}, recon.position)
    if radius < 8 or radius > 36 then
      fail("reconnaissance trajectory is not circling the target")
    end
    log("SHAHED_TEST_PASS reconnaissance drone follows a moving elliptical survey route")
  end
end)
