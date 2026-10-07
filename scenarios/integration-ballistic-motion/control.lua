local surface
local expected_step
local first_step, last_step
local previous_progress = -1
local previous_distance = math.huge
local previous_position
local distinct_samples = 0
local started = false
local starting_impacts = 0
local starting_cleanups = 0

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
  surface = game.surfaces[1]
  local target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  local site = surface.create_entity({
    name = "shahed-attack-ballistic-site",
    position = {-320, 0},
    force = game.forces.enemy,
    raise_built = true
  })
  if not target or not site then fail("could not create long-range ballistic fixture") end
  local launch = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    source_position = site.position
  })
  if not launch.ok then fail("could not launch long-range ballistic fixture") end
  local status = remote.call("shahed_attack", "get_surface_state", surface.index)
  local missile = status.missiles[1]
  if not missile then fail("launched missile is absent from diagnostics") end
  expected_step = 320 / missile.duration_ticks
  starting_impacts = status.counters.ballistic_impacts or 0
  starting_cleanups = status.counters.ballistic_cleanups or 0
end)

script.on_event(defines.events.on_tick, function(event)
  local status = remote.call("shahed_attack", "get_surface_state", surface.index)
  if status.active_missiles > 0 then
    started = true
    local missile = status.missiles[1]
    if missile.progress + 0.0000001 < previous_progress then
      fail("ballistic progress moved backward")
    end
    if missile.distance_to_target > previous_distance + 0.0001 then
      fail("ballistic missile moved away from its target")
    end
    if missile.progress > 0 then
      if missile.step_distance <= 0 then fail("ballistic step stalled") end
      first_step = first_step or missile.step_distance
      if last_step and missile.step_distance + 0.000001 < last_step then fail("ballistic acceleration reversed") end
      last_step = missile.step_distance
      if missile.step_distance > expected_step * 2.01 then fail("ballistic step teleported") end
    end
    if not previous_position or distance(previous_position, missile.position) > 0.000001 then
      distinct_samples = distinct_samples + 1
    end
    previous_position = {x = missile.position.x, y = missile.position.y}
    previous_progress = missile.progress
    previous_distance = missile.distance_to_target
  elseif started then
    if not first_step or last_step < first_step * 10 then fail("missile does not accelerate strongly") end
    if distinct_samples < 2600 then
      fail("ballistic flight produced fewer than 2600 distinct per-tick samples")
    end
    if (status.counters.ballistic_impacts or 0) ~= starting_impacts + 1 then
      fail("ballistic impact did not occur exactly once")
    end
    if (status.counters.ballistic_cleanups or 0) ~= starting_cleanups + 1 then
      fail("ballistic cleanup did not occur exactly once")
    end
    log(string.format(
      "SHAHED_TEST_PASS ballistic motion accelerates across %d distinct samples with one impact and cleanup",
      distinct_samples
    ))
    script.on_event(defines.events.on_tick, nil)
  elseif event.tick > 30 then
    fail("ballistic missile never entered the active registry")
  end
end)
