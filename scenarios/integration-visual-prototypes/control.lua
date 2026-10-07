local surface
local entities = {}
local battery
local initial_ballistic_launches = 0
local initial_abm_launches = 0

local function fail(message)
  error("SHAHED_TEST_FAIL: " .. message)
end

local function create(name, position, force)
  local entity = surface.create_entity({
    name = name,
    position = position,
    force = force,
    raise_built = true
  })
  if not entity then
    fail("could not create " .. name)
  end
  entities[#entities + 1] = entity
  return entity
end

script.on_init(function()
  game.speed = 16
  surface = game.surfaces[1]
  remote.call("shahed_attack", "set_intercept_accuracy", 1)
  local player_force = game.forces.player
  local hostile_force = game.forces["shahed-air-enemy"] or game.forces.enemy
  local target = create("assembling-machine-1", {0, 0}, player_force)
  local radar = create("shahed-attack-early-warning-radar", {-40, 20}, player_force)
  radar.energy = 10000000
  create("shahed-attack-aa-turret", {20, 20}, player_force)
  battery = create("shahed-attack-abm-battery", {-80, -20}, player_force)
  battery.energy = 20000000
  local inventory = battery.get_inventory(defines.inventory.turret_ammo)
  inventory.insert({name = "shahed-attack-interceptor", count = 2})
  create("shahed-attack-airfield", {80, 80}, hostile_force)
  local site = create("shahed-attack-ballistic-site", {-160, 0}, hostile_force)

  local recon = remote.call("shahed_attack", "schedule_event", {
    kind = "recon",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    origin_position = {x = -80, y = 20},
    size = 1
  })
  if not recon.ok then fail("could not create radar-alert drone") end

  local before = remote.call("shahed_attack", "get_surface_state", surface.index)
  initial_ballistic_launches = before.visuals.ballistic_launches
  initial_abm_launches = before.visuals.abm_launches

  local ballistic = remote.call("shahed_attack", "schedule_event", {
    kind = "ballistic",
    surface_index = surface.index,
    target_force_name = "player",
    target_position = target.position,
    source_position = site.position
  })
  if not ballistic.ok then fail("could not create local-site ballistic launch") end
end)

script.on_nth_tick(60, function(event)
  if event.tick == 120 then
    local status = remote.call("shahed_attack", "get_surface_state", surface.index)
    if status.visuals.idle ~= 2 then
      fail("airfield and ballistic-site idle overlays were not both registered")
    end
    if status.visuals.alerts < 1 then
      fail("radar alert overlay was not activated")
    end
    if status.visuals.ballistic_launches ~= initial_ballistic_launches + 1 then
      fail("ballistic launch overlay was not played exactly once")
    end
    if status.visuals.abm_launches ~= initial_abm_launches + 1 then
      fail("ABM launch overlay was not played exactly once")
    end
    for _, entity in ipairs(entities) do
      if entity.valid then entity.destroy({raise_destroy = true}) end
    end
  elseif event.tick == 180 then
    local status = remote.call("shahed_attack", "get_surface_state", surface.index)
    if status.visuals.owners ~= 0 or status.visuals.idle ~= 0 or status.visuals.alerts ~= 0 then
      fail("visual owner registry retained destroyed entities")
    end
    log("SHAHED_TEST_PASS visual overlays launch, alert, and clean up with their owners")
  end
end)

script.on_nth_tick(10, function(event)
  if event.tick == 10 then
    game.take_screenshot({
      surface = surface,
      position = {-120, 0},
      resolution = {1600, 900},
      zoom = 0.5,
      path = "shahed-launch-review.png",
      show_entity_info = true
    })
  elseif event.tick == 60 then
    game.take_screenshot({
      surface = surface,
      position = {20, 40},
      resolution = {1920, 1080},
      zoom = 0.5,
      path = "shahed-defense-review.png",
      show_entity_info = true
    })
  end
end)
