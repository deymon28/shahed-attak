-- A train with an AA wagon and an ABM wagon under a real raid: drones target
-- the train, both wagons fire, turret heads and map range circles exist.
local function check(value, message) if not value then error("SHAHED_TEST_FAIL: " .. message) end end

local surface, locomotive, aa_wagon, abm_wagon

script.on_init(function()
  game.speed = 16
  surface = game.surfaces[1]
  surface.always_day = true
  surface.request_to_generate_chunks({0, 0}, 4)
  surface.force_generate_chunk_requests()
  for _, entity in ipairs(surface.find_entities_filtered({area = {{-80, -10}, {80, 10}}})) do
    if entity.valid and entity.type ~= "character" then entity.destroy() end
  end
  for x = -70, 70, 2 do
    surface.create_entity({name = "straight-rail", position = {x, 0}, direction = defines.direction.east, force = "player"})
  end
  locomotive = surface.create_entity({name = "locomotive", position = {-10, 0}, direction = defines.direction.east,
    force = "player", raise_built = true})
  aa_wagon = surface.create_entity({name = "shahed-attack-aa-wagon", position = {-3, 0}, direction = defines.direction.east,
    force = "player", raise_built = true})
  abm_wagon = surface.create_entity({name = "shahed-attack-abm-wagon", position = {4, 0}, direction = defines.direction.east,
    force = "player", raise_built = true})
  check(locomotive and aa_wagon and abm_wagon, "train with air-defense wagons created on rails")
  check(aa_wagon.insert({name = "shahed-attack-flak-magazine", count = 5}) == 5, "AA wagon accepts flak magazines")
  locomotive.destructible = false
  surface.create_entity({name = "shahed-attack-airfield", position = {0, -160}, force = "enemy", raise_built = true})
  local result = remote.call("shahed_attack", "schedule_event", {kind = "raid", stagger = false,
    target_position = locomotive.position, origin_position = {x = 0, y = -160}, size = 6})
  check(result.ok, "raid against the train scheduled from a real airfield")
end)

local function renders(predicate)
  local count = 0
  for _, object in pairs(rendering.get_all_objects("shahed-attack")) do
    if object.valid and predicate(object) then count = count + 1 end
  end
  return count
end

script.on_event(defines.events.on_tick, function(event)
  local tick = event.tick
  if tick == 10 then
    local state = remote.call("shahed_attack", "get_surface_state", 1)
    local on_train = 0
    for _, drone in ipairs(state.drones) do
      if drone.target_position and math.abs(drone.target_position.y) < 3 then on_train = on_train + 1 end
    end
    check(on_train >= 1, "drones target the train")
    check(renders(function(o) return o.type == "animation" and o.animation:find("wagon%-head") end) == 2,
      "both wagons draw a turret head")
    check(renders(function(o) return o.type == "circle" and o.render_mode == "chart" end) >= 4,
      "wagon coverage is drawn on the map")
  end
  -- Stage 1: the AA wagon alone against the drones.
  if tick == 60 * 60 then
    local state = remote.call("shahed_attack", "get_surface_state", 1)
    check(state.counters.flak_shots > 0, "AA wagon fired flak")
    check(aa_wagon.get_item_count("shahed-attack-flak-magazine") < 5, "AA wagon consumed magazines")
    check(state.counters.drones_destroyed + state.counters.drone_impacts > 0, "the raid was resolved at the train")
    -- Stage 2: the ABM wagon against a ballistic missile aimed at the train.
    check(abm_wagon.insert({name = "shahed-attack-interceptor", count = 10}) == 10, "ABM wagon accepts interceptors")
    surface.create_entity({name = "shahed-attack-ballistic-site", position = {-600, 40}, force = "enemy", raise_built = true})
    local launch = remote.call("shahed_attack", "schedule_event", {kind = "ballistic",
      target_position = locomotive.position, source_position = {x = -600, y = 40}})
    check(launch.ok, "ballistic missile launched at the train")
  end
  if tick == 60 * 60 + 60 * 60 then
    local state = remote.call("shahed_attack", "get_surface_state", 1)
    check(state.counters.interceptor_launches > 0, "ABM wagon launched interceptors without grid power")
    check(abm_wagon.get_item_count("shahed-attack-interceptor") < 10, "ABM wagon consumed interceptors")
    log("SHAHED_TEST_PASS train targeting, AA and ABM wagons, wagon turret heads and map ranges")
    script.on_event(defines.events.on_tick, nil)
  end
end)
