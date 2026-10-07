local function check(value, message)
  if not value then error("SHAHED_TEST_FAIL: " .. message) end
end

local surface, radar
local saw_raid, saw_ballistic, saw_drone_warning, saw_ballistic_warning
local removed_at, raids_after_removal, sources_seen
local sites_removed_at, ballistic_after_removal, completed

-- The air war is fought on Nauvis only, so the test regenerates Nauvis with
-- dense biter bases instead of creating a separate surface.
script.on_init(function()
  game.speed = 1000
  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.pollution.enabled = false
  surface = game.surfaces[1]
  local settings = surface.map_gen_settings
  settings.seed = 351947
  settings.width = 2048
  settings.height = 512
  settings.water = 0
  settings.starting_area = 0.1
  settings.autoplace_controls = settings.autoplace_controls or {}
  settings.autoplace_controls["enemy-base"] = {frequency = 6, size = 4, richness = 1}
  settings.cliff_settings = settings.cliff_settings or {}
  settings.cliff_settings.cliff_elevation_interval = 0
  surface.map_gen_settings = settings
  surface.clear(true)
end)

local prepared = false
local function prepare()
  prepared = true
  surface.ticks_per_day = 2400
  surface.request_to_generate_chunks({384, 0}, 16)
  surface.force_generate_chunk_requests()
  game.forces.enemy.set_evolution_factor(0.8, surface)
  game.forces.player.technologies["chemical-science-pack"].researched = true
  local factory = surface.create_entity({name = "assembling-machine-1", position = {0, 0}, force = "player", raise_built = true})
  factory.destructible = false
  radar = surface.create_entity({name = "shahed-attack-early-warning-radar", position = {0, 8}, force = "player", raise_built = true})
  radar.destructible = false
  for _, entity in pairs(surface.find_entities_filtered({force = "enemy"})) do
    if entity.type == "unit-spawner" or entity.type == "turret" then entity.active = false end
    if entity.type == "unit" then entity.destroy() end
  end
end

script.on_event(defines.events.on_tick, function(event)
  if completed then return end
  if not prepared then
    if event.tick >= 2 then prepare() end
    return
  end
  radar.energy = 10000000
  if event.tick % 30 ~= 0 then return end
  local current = remote.call("shahed_attack", "get_surface_state", surface.index)
  if event.tick == 1200 then
    local airfields, sites = 0, 0
    for _, source in ipairs(current.sources) do
      if source.kind == "airfields" then airfields = airfields + 1 else sites = sites + 1 end
    end
    check(airfields > 0 and sites > 0, "generated enemy chunks must contain both real source types")
    sources_seen = {airfields = airfields, sites = sites}
    log("NATURAL_SOURCE_COUNTS " .. helpers.table_to_json(sources_seen))
  end
  for _, drone in ipairs(current.drones) do
    check(drone.source_unit_number, "natural drone has a real source")
    if not saw_raid then
      local found = false
      for _, source in ipairs(current.sources) do
        if source.unit_number == drone.source_unit_number then
          found = source.position.x == drone.origin.x and source.position.y == drone.origin.y
        end
      end
      check(found, "natural drone origin equals the world airfield")
      saw_raid = true
    end
  end
  for _, missile in ipairs(current.missiles) do
    check(event.tick >= 108000, "ballistics respect the full preparation period")
    check(missile.source_unit_number, "natural ballistic has a world launch site")
    saw_ballistic = true
  end
  for _, warning in ipairs(current.warnings) do
    if warning.kind == "ballistic" then
      check(warning.eta >= 30 and warning.eta <= 60, "natural ballistic warning lead time")
      saw_ballistic_warning = true
    else
      if warning.eta >= 30 and warning.eta <= 60 then saw_drone_warning = true end
    end
  end
  if event.tick < 108000 then check(current.counters.ballistic == 0, "no premature natural ballistic attack") end
  if not removed_at and event.tick >= 30000 and saw_raid and saw_drone_warning then
    for _, entity in pairs(surface.find_entities_filtered({name = "shahed-attack-airfield"})) do entity.die() end
    raids_after_removal = current.counters.raids + current.counters.recon
    removed_at = event.tick
  end
  if removed_at and event.tick > removed_at + 60 then
    check(current.counters.raids + current.counters.recon == raids_after_removal, "destroyed airfields stop new raids")
    for _, source in ipairs(current.sources) do check(source.kind ~= "airfields", "destroyed source does not regenerate") end
  end
  if not sites_removed_at and saw_ballistic and saw_ballistic_warning and removed_at then
    for _, entity in pairs(surface.find_entities_filtered({name = "shahed-attack-ballistic-site"})) do entity.die() end
    sites_removed_at = event.tick
    ballistic_after_removal = current.counters.ballistic
  end
  if sites_removed_at then
    check(current.counters.ballistic == ballistic_after_removal, "destroyed sites stop subsequent ballistic salvos")
    if event.tick > sites_removed_at + 18000 then
      completed = true
      log("SHAHED_TEST_PASS natural map generation, physical launch origins, preparation delay, early warnings and destruction of both source types")
    end
  end
  if event.tick > 180000 then
    error("SHAHED_TEST_FAIL: natural scheduler timeout " .. helpers.table_to_json({raid=saw_raid, ballistic=saw_ballistic, drone_warning=saw_drone_warning, ballistic_warning=saw_ballistic_warning, removed=removed_at, status=current}))
  end
end)
