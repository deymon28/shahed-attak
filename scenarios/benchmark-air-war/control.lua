-- Sustained heavy air war for performance measurement (tests/benchmark.ps1).
-- Uses only remote calls that exist in 0.6.x and 0.7.x so both versions
-- can be measured on the same world: raids start at airfields placed at
-- the requested origin positions, missiles at a placed launch site.
local surface
local targets = {}
local batteries = {}
local radars = {}
local ORIGINS = {{x = -560, y = 0}, {x = 560, y = 0}, {x = 0, y = -560}, {x = 0, y = 560}}
local SAVE_TICK = 900

local function place(name, position, force)
  return surface.create_entity({name = name, position = position, force = force or "player", raise_built = true})
end

script.on_init(function()
  surface = game.surfaces[1]
  surface.always_day = true
  surface.peaceful_mode = true
  surface.request_to_generate_chunks({0, 0}, 20)
  surface.force_generate_chunk_requests()
  for _, entity in ipairs(surface.find_entities_filtered({area = {{-80, -80}, {80, 80}}, type = {"tree", "simple-entity", "cliff", "unit-spawner", "turret", "unit"}})) do
    entity.destroy()
  end
  -- Factory: 20 x 20 assembling machines.
  for x = -19, 19, 2 do
    for y = -19, 19, 2 do
      targets[#targets + 1] = place("assembling-machine-1", {x * 2, y * 2})
    end
  end
  -- Air defense ring: 48 AA turrets, 24 ABM batteries, 16 radars.
  for index = 0, 47 do
    local angle = index / 48 * math.pi * 2
    local turret = place("shahed-attack-aa-turret", {math.cos(angle) * 56, math.sin(angle) * 56})
    turret.insert({name = "shahed-attack-flak-magazine", count = 200})
  end
  for index = 0, 23 do
    local angle = index / 24 * math.pi * 2
    local battery = place("shahed-attack-abm-battery", {math.cos(angle) * 66, math.sin(angle) * 66})
    battery.insert({name = "shahed-attack-interceptor", count = 20})
    batteries[#batteries + 1] = battery
  end
  for index = 0, 15 do
    local angle = index / 16 * math.pi * 2
    radars[#radars + 1] = place("shahed-attack-early-warning-radar", {math.cos(angle) * 74, math.sin(angle) * 74})
  end
  for _, origin in ipairs(ORIGINS) do
    place("shahed-attack-airfield", origin, "enemy")
  end
  place("shahed-attack-ballistic-site", {x = 1400, y = 300}, "enemy")
  remote.call("shahed_attack", "set_intercept_accuracy", 0.5)
end)

local function attack(tick)
  if tick % 300 == 30 then
    for index, origin in ipairs(ORIGINS) do
      local target = targets[(tick / 30 + index * 37) % #targets + 1]
      if target.valid then
        remote.call("shahed_attack", "schedule_event", {kind = "raid", target_position = target.position,
          origin_position = origin, size = 10, stagger = false})
      end
    end
  end
  if tick % 120 == 60 then
    local target = targets[(tick / 60 * 13) % #targets + 1]
    if target.valid then
      remote.call("shahed_attack", "schedule_event", {kind = "ballistic", target_position = target.position,
        source_position = {x = 1400, y = 300}})
    end
  end
end

script.on_event(defines.events.on_tick, function(event)
  for _, battery in ipairs(batteries) do
    if battery.valid then
      battery.energy = 20000000
      if battery.get_item_count("shahed-attack-interceptor") < 5 then
        battery.insert({name = "shahed-attack-interceptor", count = 10})
      end
    end
  end
  for _, radar in ipairs(radars) do
    if radar.valid then radar.energy = 10000000 end
  end
  attack(event.tick)
  -- Per-handler timing where the measured version provides it.
  local profiling = remote.interfaces["shahed_attack"] and remote.interfaces["shahed_attack"]["start_profiling"]
  if profiling and event.tick == SAVE_TICK - 600 then remote.call("shahed_attack", "start_profiling") end
  if profiling and event.tick == SAVE_TICK - 1 then remote.call("shahed_attack", "stop_profiling") end
  if event.tick == SAVE_TICK then
    game.server_save("benchmark")
    log("SHAHED_BENCH_SAVED")
  end
end)
