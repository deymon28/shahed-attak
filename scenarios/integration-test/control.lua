local test_state = {
  started = false,
  verified = false,
  obstacle_checked = false,
  batteries = {}
}

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  local player_force = game.forces.player
  game.forces.enemy.set_evolution_factor(0.8, surface)
  surface.always_day = true

  local target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = player_force,
    raise_built = true
  })
  if not target then
    fail("could not create target assembler")
  end

  local radar = surface.create_entity({
    name = "shahed-attack-early-warning-radar",
    position = {0, 12},
    force = player_force,
    raise_built = true
  })
  if not radar then
    fail("could not create warning radar")
  end
  local substation = surface.create_entity({
    name = "substation",
    position = {3, 12},
    force = player_force
  })
  local power_source = surface.create_entity({
    name = "electric-energy-interface",
    position = {6, 12},
    force = player_force
  })
  if not substation or not power_source then
    fail("could not create test power network")
  end

  for x = -6, 6 do
    surface.create_entity({name = "stone-wall", position = {x, -15}, force = player_force})
  end
  local obstacle_drone = surface.create_entity({
    name = "shahed-attack-heavy-drone",
    position = {0, -25},
    force = "enemy"
  })
  if not obstacle_drone or not obstacle_drone.commandable then
    fail("could not create obstacle test drone")
  end
  obstacle_drone.commandable.set_command({
    type = defines.command.go_to_location,
    destination = {0, -5},
    radius = 1,
    distraction = defines.distraction.none
  })
  test_state.obstacle_drone = obstacle_drone

  local weapon_drone = surface.create_entity({
    name = "shahed-attack-heavy-drone",
    position = {500, -8},
    force = "enemy"
  })
  local gun_turret = surface.create_entity({name = "gun-turret", position = {500, 0}, force = player_force})
  if not weapon_drone or not gun_turret then
    fail("could not create ordinary weapon test")
  end
  weapon_drone.commandable.set_command({type = defines.command.stop, distraction = defines.distraction.none})
  gun_turret.insert({name = "piercing-rounds-magazine", count = 20})
  test_state.weapon_drone = weapon_drone

  local aa_drone = surface.create_entity({
    name = "shahed-attack-heavy-drone",
    position = {600, -16},
    force = "enemy"
  })
  local aa_turret = surface.create_entity({
    name = "shahed-attack-aa-turret",
    position = {600, 0},
    force = player_force,
    raise_built = true
  })
  if not aa_drone or not aa_turret then
    fail("could not create anti-air weapon test")
  end
  aa_drone.commandable.set_command({type = defines.command.stop, distraction = defines.distraction.none})
  aa_turret.insert({name = "shahed-attack-flak-magazine", count = 20})
  test_state.aa_drone = aa_drone
  test_state.aa_turret = aa_turret

  for index = 0, 7 do
    local angle = index * math.pi / 4
    local battery = surface.create_entity({
      name = "shahed-attack-abm-battery",
      position = {math.cos(angle) * 80, math.sin(angle) * 80},
      force = player_force,
      raise_built = true
    })
    if battery then
      battery.energy = 20000000
      battery.insert({name = "shahed-attack-interceptor", count = 1})
      test_state.batteries[#test_state.batteries + 1] = battery
    end
  end

  local raid = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    size = 6
  })
  if not raid.ok then
    fail("raid creation failed: " .. tostring(raid.error))
  end

  local missile = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position
  })
  if not missile.ok then
    fail("ballistic creation failed: " .. tostring(missile.error))
  end
  test_state.started = true
end)

script.on_nth_tick(120, function(event)
  if not test_state.started or test_state.verified then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  if not current then
    fail("surface state is unavailable")
  end
  if current.counters.raids < 1 then
    fail("raid counter was not incremented")
  end
  if current.counters.ballistic < 1 then
    fail("ballistic counter was not incremented")
  end
  if event.tick >= 360 and not test_state.obstacle_checked then
    if not test_state.obstacle_drone.valid or test_state.obstacle_drone.position.y <= -15 then
      fail("air drone did not cross the solid wall line")
    end
    test_state.obstacle_checked = true
  end
  if event.tick >= 3700 then
    if not test_state.obstacle_checked then
      fail("obstacle collision check did not run")
    end
    if current.active_missiles ~= 0 then
      fail("ballistic missile did not resolve within the expected flight time")
    end
    if not test_state.weapon_drone.valid then
      fail("ordinary gun turret damaged an aerial drone")
    end
    if test_state.aa_drone.valid then
      fail(string.format(
        "anti-air turret did not destroy an aerial drone: health=%.1f shots=%d hits=%d misses=%d ammo=%d",
        test_state.aa_drone.health or -1,
        current.counters.flak_shots or 0,
        current.counters.flak_hits or 0,
        current.counters.flak_misses or 0,
        test_state.aa_turret.valid
          and test_state.aa_turret.get_item_count("shahed-attack-flak-magazine") or -1
      ))
    end
    local interceptors = 0
    for _, battery in ipairs(test_state.batteries) do
      if battery.valid then
        interceptors = interceptors + battery.get_item_count("shahed-attack-interceptor")
      end
    end
    if interceptors >= #test_state.batteries then
      fail("no missile-defense battery consumed an interceptor")
    end
    test_state.verified = true
    log(string.format(
      "SHAHED_TEST_PASS raids=%d ballistic=%d intercepted=%d interceptors_left=%d active_drones=%d active_missiles=%d",
      current.counters.raids,
      current.counters.ballistic,
      current.counters.intercepted,
      interceptors,
      current.active_drones,
      current.active_missiles
    ))
  end
end)
