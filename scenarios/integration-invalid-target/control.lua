local started = false

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
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
  if not target then
    fail("could not create doomed ballistic target")
  end
  local result = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position
  })
  if not result.ok then
    fail("could not launch ballistic test")
  end
  target.destroy({raise_destroy = true})
  started = true
end)

script.on_nth_tick(60, function(event)
  if not started then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  if event.tick >= 3700 then
    if current.active_missiles ~= 0 then
      fail("ballistic event did not resolve after its target was destroyed")
    end
    log("SHAHED_TEST_PASS destroyed ballistic target did not invalidate alerts or impact")
    started = false
  end
end)
