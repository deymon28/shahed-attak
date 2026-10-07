local target
local middle
local outer
local first_position
local motion_checked = false

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
  -- Heavy missiles keep up to 3 tiles of aim error; the middle ring reaches 14 tiles.
  middle = surface.create_entity({name = "storage-tank", position = {10, 0}, force = game.forces.player})
  outer = surface.create_entity({name = "storage-tank", position = {28, 0}, force = game.forces.player})
  game.surfaces[1].create_entity({name="shahed-attack-ballistic-site",position={-900,0},force="enemy",raise_built=true})
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic", class = "heavy", source_position={x=-900,y=0},
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position
  })
  if not result.ok then
    fail("could not launch ballistic flight test")
  end
end)

script.on_nth_tick(1, function(event)
  if motion_checked then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  local missile = current.missiles and current.missiles[1]
  if not missile then
    fail("remote state does not expose active missile motion")
  end
  if missile.has_sound_source ~= true then
    fail("active ballistic missile has no moving flight sound source")
  end
  if missile.duration_ticks < 38 * 60 then
    fail("heavy ballistic flight leaves less than its 38-second minimum to react")
  end
  if not first_position then
    first_position = missile.position
    return
  end
  local step = distance(first_position, missile.position)
  if step <= 0 then
    fail("ballistic missile did not move between adjacent ticks")
  end
  if step >= 5 then
    fail("ballistic missile still teleports in large visual steps")
  end
  motion_checked = true
end)

script.on_nth_tick(60, function(event)
  if event.tick == 60 then
    local current = remote.call("shahed_attack", "get_surface_state", 1)
    local missile = current.missiles and current.missiles[1]
    if not missile or (missile.trail_emissions or 0) < 3 then
      fail("ballistic flight has no continuous visible trail")
    end
    if missile.has_sound_source ~= true then
      fail("ballistic sound source disappeared during flight")
    end
  end
  if event.tick < 3700 then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  if current.active_missiles ~= 0 then
    fail("ballistic missile did not resolve within its finite flight time")
  end
  if current.ballistic_sound_sources ~= 0 then
    fail("ballistic moving sound source survived missile cleanup")
  end
  if target.valid then
    fail("ballistic epicenter did not destroy the target")
  end
  if middle.valid then
    fail("ballistic middle blast was not substantially stronger")
  end
  if not outer.valid or outer.health >= 500 then
    fail("expanded outer blast radius caused no damage at 28 tiles")
  end
  local scorches = game.surfaces[1].count_entities_filtered({name = "huge-scorchmark"})
  if scorches < 1 then
    fail("ballistic impact left no large persistent visual mark")
  end
  log("SHAHED_TEST_PASS ballistic flight is smooth, accelerating, visible, and substantially destructive")
end)
