local fixtures = {}

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function keep(entity)
  if entity then
    fixtures[#fixtures + 1] = entity
  end
  return entity
end

local function assert_prototypes(surface)
  local one_shots = {
    "drone-flyby",
    "flak-burst",
    "drone-impact",
    "heavy-impact",
    "wreck-impact",
    "fuel-explosion",
    "warhead-explosion",
    "ballistic-launch",
    "ballistic-impact",
    "intercept-launch",
    "intercept-burst",
    "radar-ping",
    "air-raid-siren",
    "ballistic-warning"
  }
  for _, stem in ipairs(one_shots) do
    local prototype_name = "shahed-attack-" .. stem
    local ok = pcall(function()
      surface.play_sound({path = prototype_name, position = {0, 0}})
    end)
    if not ok then
      fail("runtime sound prototype cannot be played: " .. prototype_name)
    end
  end

  local continuous = {
    "shahed-attack-recon-drone",
    "shahed-attack-strike-drone",
    "shahed-attack-heavy-drone",
    "shahed-attack-early-warning-radar",
    "shahed-attack-airfield",
    "shahed-attack-ballistic-site"
  }
  for _, name in ipairs(continuous) do
    local prototype = prototypes.entity[name]
    if not prototype then
      fail("missing continuous-audio entity prototype " .. name)
    end
  end
  if not prototypes.entity["shahed-attack-ballistic-sound-source"] then
    fail("missing moving ballistic sound-source prototype")
  end
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  assert_prototypes(surface)
  local player_force = game.forces.player
  surface.always_day = true
  game.forces.enemy.set_evolution_factor(0.8, surface)

  local target = keep(surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = player_force,
    raise_built = true
  }))
  local radar = keep(surface.create_entity({
    name = "shahed-attack-early-warning-radar",
    position = {0, 20},
    force = player_force,
    raise_built = true
  }))
  keep(surface.create_entity({name = "substation", position = {4, 20}, force = player_force}))
  keep(surface.create_entity({name = "electric-energy-interface", position = {7, 20}, force = player_force}))
  if not target or not radar then
    fail("could not create powered audio fixtures")
  end
  radar.energy = 10000000

  local aa_drone = keep(surface.create_entity({
    name = "shahed-attack-heavy-drone",
    position = {300, -16},
    force = "enemy"
  }))
  local aa_turret = keep(surface.create_entity({
    name = "shahed-attack-aa-turret",
    position = {300, 0},
    force = player_force,
    raise_built = true
  }))
  if not aa_drone or not aa_turret then
    fail("could not create flak audio fixtures")
  end
  aa_drone.commandable.set_command({type = defines.command.stop, distraction = defines.distraction.none})
  aa_turret.insert({name = "shahed-attack-flak-magazine", count = 20})

  for index = 0, 7 do
    local angle = index * math.pi / 4
    local battery = keep(surface.create_entity({
      name = "shahed-attack-abm-battery",
      position = {math.cos(angle) * 80, math.sin(angle) * 80},
      force = player_force,
      raise_built = true
    }))
    if battery then
      battery.energy = 20000000
      battery.insert({name = "shahed-attack-interceptor", count = 1})
    end
  end

  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={0,-80},force="enemy",raise_built=true})
  local raid = remote.call("shahed_attack", "schedule_event", {
    kind = "raid", stagger=false,
    surface_index = 1,
    target_force_name = "player",
    target_position = target.position,
    origin_position = {x = 0, y = -80},
    size = 2
  })
  game.surfaces[1].create_entity({name="shahed-attack-ballistic-site",position={-900,0},force="enemy",raise_built=true})
  local missile = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic", source_position={x=-900,y=0},
    surface_index = 1,
    target_force_name = "player",
    target_position = target.position
  })
  if not raid or not raid.ok or not missile or not missile.ok then
    fail("could not schedule audio coverage events")
  end
end)

script.on_nth_tick(60, function(event)
  if event.tick < 3700 then
    return
  end
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  local counters = current.audio_counters
  if not counters then
    fail("remote state does not expose audio dispatch counters")
  end
  if (counters["shahed-attack-ballistic-launch"] or 0) < 1 then
    fail("ballistic launch audio was not dispatched")
  end
  if (current.counters.flak_shots or 0) < 1 then
    fail("native AA firing did not run its prototype shot sound")
  end
  local resolved = (counters["shahed-attack-ballistic-impact"] or 0)
    + (counters["shahed-attack-intercept-burst"] or 0)
    + (counters["shahed-attack-drone-impact"] or 0)
    + (counters["shahed-attack-heavy-impact"] or 0)
  if resolved < 1 then
    fail("no impact or successful intercept audio was dispatched")
  end

  for _, entity in ipairs(fixtures) do
    if entity.valid then
      entity.destroy({raise_destroy = true})
    end
  end
  log("SHAHED_TEST_PASS runtime audio prototypes and combat dispatch counters are complete")
end)
