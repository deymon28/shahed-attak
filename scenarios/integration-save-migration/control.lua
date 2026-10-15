local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function current_version()
  return script.active_mods["shahed-attack"]
end

script.on_init(function()
  storage.original_version = current_version()
  game.speed = 16
  local surface = game.surfaces[1]
  local target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  local airfield = surface.create_entity({
    name = "shahed-attack-airfield",
    position = {80, 80},
    force = game.forces.enemy,
    raise_built = true
  })
  local site = surface.create_entity({
    name = "shahed-attack-ballistic-site",
    position = {-280, 0},
    force = game.forces.enemy,
    raise_built = true
  })
  local radar = surface.create_entity({
    name = "shahed-attack-early-warning-radar",
    position = {-40, 30},
    force = game.forces.player,
    raise_built = true
  })
  if not target or not airfield or not site or not radar then
    fail("could not create migration entities")
  end
  radar.energy = 10000000
  local raid = remote.call("shahed_attack", "schedule_event", {
    kind = "raid",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    -- The airfield itself: 0.7+ start raids only at a registered base there.
    origin_position = {x = 80, y = 80},
    size = 2
  })
  local ballistic = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic",
    -- The launch site (0.7.0 needs the hint when called before its on_init).
    origin_position = {x = -280, y = 0},
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position
  })
  if not raid.ok or not ballistic.ok then
    fail("could not create active migration threats: raid=" .. tostring(raid.error)
      .. " ballistic=" .. tostring(ballistic.error))
  end
  local status = remote.call("shahed_attack", "get_surface_state", surface.index)
  storage.fixture = {
    surface_index = surface.index,
    active_drones = status.active_drones,
    active_missiles = status.active_missiles,
    events = status.counters.events,
    raids = status.counters.raids,
    ballistic = status.counters.ballistic,
    next_raid_tick = status.next_raid_tick,
    preference_marker = "personal-alert-sound-muted"
  }
end)

script.on_configuration_changed(function()
  if current_version() ~= storage.original_version then
    -- Validate after the 80-tick launch animation of the fixture missile,
    -- which hides the launch site's idle overlay while it plays.
    storage.validate_migration_tick = math.max(game.tick + 5, 120)
  end
end)

script.on_nth_tick(1, function(event)
  if current_version() == storage.original_version and event.tick == 30 then
    storage.fixture_save_requested = true
    game.server_save("migration-fixture")
    return
  elseif current_version() == storage.original_version and event.tick == 31 and storage.fixture_save_requested then
    log("SHAHED_MIGRATION_STAGE1_READY")
    return
  end
  if current_version() == storage.original_version or not storage.validate_migration_tick
    or event.tick < storage.validate_migration_tick then
    return
  end
  local fixture = storage.fixture
  if not fixture or fixture.preference_marker ~= "personal-alert-sound-muted" then
    fail("scenario-owned preference marker did not survive the save upgrade")
  end
  local status = remote.call("shahed_attack", "get_surface_state", fixture.surface_index)
  if not status then fail("Current surface state is missing") end
  if status.schema_version < 5 then fail("storage schema was not upgraded") end
  if status.active_drones ~= fixture.active_drones then fail("active raid changed during migration") end
  if status.active_missiles ~= fixture.active_missiles then fail("active missile changed during migration") end
  if status.counters.events ~= fixture.events
    or status.counters.raids ~= fixture.raids
    or status.counters.ballistic ~= fixture.ballistic then
    fail("gameplay counters changed during migration")
  end
  if status.next_raid_tick ~= fixture.next_raid_tick then fail("raid schedule changed during migration") end
  for name, present in pairs(status.helper_tables) do
    if not present then fail("helper table is missing: " .. name) end
  end
  if #status.radar_signals ~= 1 then fail("migration did not create exactly one radar relay") end
  if status.visuals.idle ~= 2 then fail("migration did not repair two infrastructure overlays") end
  local surface = game.get_surface(fixture.surface_index)
  if #surface.find_entities_filtered({name = "shahed-attack-airfield"}) ~= 1 then
    fail("airfield did not survive migration")
  end
  if #surface.find_entities_filtered({name = "shahed-attack-ballistic-site"}) ~= 1 then
    fail("ballistic site did not survive migration")
  end
  storage.validate_migration_tick = nil
  log("SHAHED_TEST_PASS active threats and infrastructure migrated idempotently")
end)
