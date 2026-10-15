-- Buildings of a force absorbed by game.merge_forces become targets of the
-- destination force (the target registry is rebuilt after the merge).
local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

-- Without a target position the mod samples its own target registry.
local function registry_raid(force_name)
  return remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger = false, target_force_name = force_name, size = 2
  })
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local blue = game.create_force("blue")
  local lab = surface.create_entity({name = "lab", position = {0, 0}, force = blue, raise_built = true})
  local airfield = surface.create_entity({name = "shahed-attack-airfield", position = {-200, 0}, force = "enemy",
    raise_built = true})
  if not lab or not airfield then
    fail("could not create force-merge entities")
  end
  storage.lab = lab
  storage.stage = "registered"
  -- The mod's initial target scan reads 8 chunks per second; merging after it
  -- has finished makes the destination force depend on the merge handler.
  local chunks = 0
  for _ in surface.get_chunks() do chunks = chunks + 1 end
  storage.merge_tick = (math.ceil(chunks / 8) + 5) * 60
end)

script.on_nth_tick(60, function(event)
  local lab = storage.lab
  if not storage.stage then
    return
  end
  if not (lab and lab.valid) then
    fail("lab was destroyed")
  end
  if event.tick > storage.merge_tick + 60 * 60 * 30 then
    fail("test timed out in stage " .. storage.stage)
  end
  if storage.stage == "registered" and event.tick >= storage.merge_tick then
    -- Merge only after the lab is listed for its original force.
    local result = registry_raid("blue")
    if result.ok then
      remote.call("shahed_attack", "clear_threats", 1)
      game.merge_forces("blue", "player")
      storage.stage = "merged"
    end
  elseif storage.stage == "merged" and lab.force.name == "player" then
    local result = registry_raid("player")
    if result.ok then
      local state = remote.call("shahed_attack", "get_surface_state", 1)
      for _, drone in ipairs(state.drones) do
        if drone.target_position.x ~= lab.position.x or drone.target_position.y ~= lab.position.y then
          fail("raid did not target the merged lab")
        end
      end
      log("SHAHED_TEST_PASS merged force buildings are registered for the destination force")
      storage.stage = nil
    elseif result.error ~= "no-target" then
      fail("unexpected schedule error: " .. tostring(result.error))
    end
  end
end)
