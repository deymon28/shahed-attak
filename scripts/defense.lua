-- Air-defense registry and fire control.
-- ABM launchers (fixed batteries and rail wagons) keep a small magazine of
-- ready canisters, reload them one by one, and follow a fire doctrine that
-- limits how many interceptors are in flight against a single target.
local audio = require("scripts.audio")
local config = require("scripts.lib.config")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local ordnance = require("scripts.ordnance")
local rules = require("scripts.lib.air_rules")
local state = require("scripts.state")

local defense = {}

local BATTERY = "shahed-attack-abm-battery"
local ABM_WAGON = "shahed-attack-abm-wagon"
local AA_WAGON = "shahed-attack-aa-wagon"
local INTERCEPTOR = "shahed-attack-interceptor"
local FLAK_MAGAZINE = "shahed-attack-flak-magazine"

local DEFENSE_NAMES = {
  ["shahed-attack-early-warning-radar"] = "radars",
  ["shahed-attack-aa-turret"] = "aa_turrets",
  [BATTERY] = "abm_batteries",
  [AA_WAGON] = "aa_wagons",
  [ABM_WAGON] = "abm_wagons"
}
defense.DEFENSE_NAMES = DEFENSE_NAMES

local WAGON_HEADS = {
  [AA_WAGON] = "shahed-attack-aa-wagon-head",
  [ABM_WAGON] = "shahed-attack-abm-wagon-head"
}

local DEFAULT_MODES = {[BATTERY] = "ballistic", [ABM_WAGON] = "both"}
local DRONE_TARGET_KINDS = {strike = true, heavy = true, decoy = true}

function defense.is_abm_launcher(entity)
  return entity ~= nil and entity.valid and DEFAULT_MODES[entity.name] ~= nil
end

local function is_wagon(entity)
  return entity.name == ABM_WAGON or entity.name == AA_WAGON
end

function defense.launcher_range(entity)
  return entity.name == ABM_WAGON and rules.ABM_WAGON_RANGE or rules.ABM_RANGE
end

-- Fixed batteries and radars never move, so their position is read from
-- the engine once; rail launchers report their live position. The cache is
-- derived state only (rebuilt identically on every peer after loading).
local position_cache = {}
local function launcher_position(launcher)
  if is_wagon(launcher) then
    return launcher.position
  end
  local cached = position_cache[launcher.unit_number]
  if not cached then
    cached = launcher.position
    position_cache[launcher.unit_number] = cached
  end
  return cached
end
defense.launcher_position = launcher_position

local function launcher_inventory(entity)
  if is_wagon(entity) then
    return entity.get_inventory(defines.inventory.cargo_wagon)
  end
  return entity.get_inventory(defines.inventory.turret_ammo)
end

-- Rail launchers carry their own generators; fixed batteries need grid power.
local function has_energy(entity)
  return is_wagon(entity) or entity.energy >= rules.ABM_ENERGY
end

local function item_count(entity, name)
  local inventory = launcher_inventory(entity)
  return inventory and inventory.get_item_count(name) or 0
end

local function consume(entity, name)
  local inventory = launcher_inventory(entity)
  if not inventory or inventory.get_item_count(name) < 1 then
    return false
  end
  return inventory.remove({name = name, count = 1}) == 1
end

-- Target modes ------------------------------------------------------------

function defense.get_mode(launcher)
  local surface_state = state.get_surface(launcher.surface.index)
  local mode = surface_state and surface_state.battery_modes[launcher.unit_number]
  if mode == "ballistic" or mode == "both" or mode == "drones" then
    return mode
  end
  return DEFAULT_MODES[launcher.name] or "ballistic"
end

function defense.set_mode(launcher, mode)
  if not defense.is_abm_launcher(launcher)
    or (mode ~= "ballistic" and mode ~= "both" and mode ~= "drones") then
    return false
  end
  local surface_state = state.get_surface(launcher.surface.index)
  if not surface_state then
    return false
  end
  if defense.get_mode(launcher) ~= mode then
    surface_state.battery_modes[launcher.unit_number] = mode ~= DEFAULT_MODES[launcher.name] and mode or nil
    surface_state.battery_tracking[launcher.unit_number] = nil
  end
  return true
end

-- Registry ------------------------------------------------------------------

local function wagon_record(surface_state, entity)
  local record = surface_state.wagon_state[entity.unit_number]
  if not record then
    record = {heading = 0, next_shot = 0, flak_rounds = 0}
    surface_state.wagon_state[entity.unit_number] = record
  end
  return record
end

local function direction_frame(heading)
  return math.floor((heading or 0) * 64 + 0.5) % 64
end

local function ensure_wagon_head(surface_state, entity)
  local animation = WAGON_HEADS[entity.name]
  if not animation then
    return
  end
  local record = wagon_record(surface_state, entity)
  if record.head and record.head.valid then
    return
  end
  record.head = rendering.draw_animation({
    animation = animation,
    target = {entity = entity, offset = {0, -0.45}},
    surface = entity.surface,
    render_layer = "higher-object-under",
    animation_speed = 0,
    animation_offset = direction_frame(record.heading),
    x_scale = 0.7,
    y_scale = 0.7
  })
end

local function set_heading(surface_state, entity, heading)
  if is_wagon(entity) then
    local record = wagon_record(surface_state, entity)
    record.heading = heading
    if record.head and record.head.valid then
      record.head.animation_offset = direction_frame(heading)
    end
  else
    entity.orientation = heading
  end
end

local function get_heading(surface_state, entity)
  if is_wagon(entity) then
    return wagon_record(surface_state, entity).heading
  end
  return entity.orientation or 0
end

local function register(entity, defense_type)
  local surface_state = state.ensure_surface(entity.surface)
  if not surface_state then
    return
  end
  local list = surface_state.defenses[defense_type]
  if list[entity.unit_number] then
    ensure_wagon_head(surface_state, entity)
    return
  end
  list[entity.unit_number] = entity
  local registration = script.register_on_object_destroyed(entity)
  state.root().defense_registrations[registration] = {
    surface_index = entity.surface.index,
    unit_number = entity.unit_number,
    defense_type = defense_type
  }
  ensure_wagon_head(surface_state, entity)
end

function defense.initialize()
  for _, surface in pairs(game.surfaces) do
    if state.supported(surface) then
      for name, defense_type in pairs(DEFENSE_NAMES) do
        for _, entity in ipairs(surface.find_entities_filtered({name = name})) do
          register(entity, defense_type)
        end
      end
    end
  end
end

function defense.on_entity_created(entity)
  local defense_type = entity and entity.valid and DEFENSE_NAMES[entity.name]
  if defense_type then
    register(entity, defense_type)
  end
end

function defense.on_object_destroyed(event)
  local root = state.root()
  local record = root.defense_registrations[event.registration_number]
  if not record then
    return
  end
  root.defense_registrations[event.registration_number] = nil
  local surface_state = state.get_surface(record.surface_index)
  if surface_state then
    local unit = record.unit_number
    position_cache[unit] = nil
    surface_state.defenses[record.defense_type][unit] = nil
    surface_state.battery_modes[unit] = nil
    surface_state.battery_tracking[unit] = nil
    surface_state.battery_next_shot[unit] = nil
    surface_state.launcher_rounds[unit] = nil
    local wagon = surface_state.wagon_state[unit]
    if wagon and wagon.head and wagon.head.valid then wagon.head.destroy() end
    surface_state.wagon_state[unit] = nil
  end
end

local function powered(entity, required_energy)
  return entity.valid and entity.energy >= (required_energy or 1000)
end

function defense.tracking_for_position(surface_state, force_index, position, threat_kind)
  local range = threat_kind == "ballistic" and rules.BALLISTIC_RADAR_RANGE or rules.DRONE_RADAR_RANGE
  local best = 0
  for _, radar in pairs(surface_state.defenses.radars) do
    if radar.valid and radar.force.index == force_index and powered(radar, 1000) then
      local distance = defense_math.distance(launcher_position(radar), position)
      if distance <= range then
        best = math.max(best, math.max(0.01, 1 - distance / range))
      end
    end
  end
  return best
end

-- Magazine ----------------------------------------------------------------

local function magazine(surface_state, launcher, tick)
  local record = surface_state.launcher_rounds[launcher.unit_number]
  if not record then
    record = {rounds = rules.ABM_MAGAZINE}
    surface_state.launcher_rounds[launcher.unit_number] = record
  end
  record.rounds, record.reload_tick = rules.reload_magazine(record.rounds, record.reload_tick, tick)
  return record
end

function defense.launcher_status(launcher)
  local surface_state = state.get_surface(launcher.surface.index)
  if not surface_state then
    return {key = "ready", ammo = 0, rounds = 0}
  end
  local tick = game.tick
  local record = magazine(surface_state, launcher, tick)
  local ammo = item_count(launcher, INTERCEPTOR)
  local key
  if ammo == 0 then
    key = "no-ammo"
  elseif not has_energy(launcher) then
    key = "charging"
  elseif record.rounds == 0 or tick < (surface_state.battery_next_shot[launcher.unit_number] or 0) then
    key = "reloading"
  else
    key = "ready"
  end
  return {key = key, ammo = ammo, rounds = math.min(record.rounds, ammo), reload_tick = record.reload_tick}
end

local function show_status(launcher, key, color)
  if is_wagon(launcher) then
    return
  end
  launcher.custom_status = {
    diode = defines.entity_status_diode[color or "green"],
    label = {"shahed-attack-status." .. key}
  }
end

local STATUS_COLORS = {["no-ammo"] = "red", charging = "yellow", reloading = "yellow"}

-- Fire control --------------------------------------------------------------

local function target_key(target)
  if target.drone then
    return "d" .. target.drone.unit_number
  end
  return "m" .. target.id
end

local function hit_probability(target)
  local accuracy = config.global("shahed-attack-intercept-accuracy", rules.INTERCEPT_ACCURACY)
  if target.drone then
    return rules.intercept_probability(accuracy, rules.DRONE_HIT_FACTOR)
  end
  return rules.intercept_probability(accuracy, rules.class_stats(target.class).hit_factor)
end

local function same_target(lock, target)
  return lock.missile_id == target.id and lock.target_drone == target.drone
end

local function aim_at(surface_state, launcher, target)
  local tracking = surface_state.battery_tracking
  local lock = tracking[launcher.unit_number]
  if lock and not same_target(lock, target) then
    -- Keep the current lock while its target remains alive and in range.
    local previous
    if lock.target_drone then
      previous = lock.target_drone.valid and lock.target_drone or nil
    elseif lock.missile_id then
      local missile = surface_state.active_missiles[lock.missile_id]
      previous = missile and not missile.intercepted and not missile.finished and missile or nil
    end
    if previous and defense_math.distance(launcher_position(launcher), previous.position) <= defense.launcher_range(launcher) then
      return false
    end
    lock = nil
  end
  if not lock then
    lock = {battery = launcher, missile_id = target.id, target_drone = target.drone,
      acquired_tick = game.tick, updated_tick = game.tick}
    tracking[launcher.unit_number] = lock
  end
  local desired = flight_math.orientation(launcher_position(launcher), target.position)
  local heading = get_heading(surface_state, launcher)
  local difference = (desired - heading + 0.5) % 1 - 0.5
  local step = rules.ABM_TURN_RATE * math.max(0, game.tick - lock.updated_tick)
  set_heading(surface_state, launcher, (heading + math.max(-step, math.min(step, difference))) % 1)
  lock.updated_tick = game.tick
  return math.abs(difference) <= step + 0.000001 and game.tick - lock.acquired_tick >= rules.ABM_AIM_TICKS
end

local function release_lock(surface_state, launcher, target)
  local lock = surface_state.battery_tracking[launcher.unit_number]
  if lock and same_target(lock, target) then
    surface_state.battery_tracking[launcher.unit_number] = nil
  end
end

local function try_intercept(launcher, target, surface_state)
  local tick = game.tick
  local distance = defense_math.distance(launcher_position(launcher), target.position)
  if distance > defense.launcher_range(launcher) then
    release_lock(surface_state, launcher, target)
    return
  end
  local ammunition = item_count(launcher, INTERCEPTOR)
  local record = magazine(surface_state, launcher, tick)
  local key = target_key(target)
  local limit = config.global("shahed-attack-interceptors-per-target")
  local saturated = ordnance.engaged(surface_state, key) >= limit
  local ready_to_aim = ammunition > 0 and has_energy(launcher) and record.rounds > 0
  if not ready_to_aim then
    release_lock(surface_state, launcher, target)
  end
  local aimed = ready_to_aim and aim_at(surface_state, launcher, target)
  local next_tick = surface_state.battery_next_shot[launcher.unit_number] or 0
  if aimed and not saturated and tick >= next_tick and consume(launcher, INTERCEPTOR) then
    if not is_wagon(launcher) then
      launcher.energy = launcher.energy - rules.ABM_ENERGY
    end
    record.rounds = record.rounds - 1
    record.reload_tick = record.reload_tick or (tick + rules.ABM_RELOAD_TICKS)
    surface_state.battery_next_shot[launcher.unit_number] = tick + rules.ABM_COOLDOWN
    ordnance.launch_interceptor(surface_state, launcher, target, hit_probability(target), key)
    surface_state.counters.interceptor_launches = surface_state.counters.interceptor_launches + 1
    audio.play(launcher.surface, "shahed-attack-intercept-launch", launcher.position,
      "intercept-launch::" .. launcher.unit_number, 15)
    show_status(launcher, target.drone and "engaging-drone" or "engaging")
  elseif ammunition == 0 then
    show_status(launcher, "no-ammo", "red")
  elseif not has_energy(launcher) then
    show_status(launcher, "charging", "yellow")
  elseif record.rounds == 0 or tick < next_tick then
    show_status(launcher, "reloading", "yellow")
  else
    show_status(launcher, target.drone and "engaging-drone" or "engaging")
  end
end

local function abm_launchers(surface_state)
  return {surface_state.defenses.abm_batteries, surface_state.defenses.abm_wagons}
end

-- Launchers of a force that may reach a position soon (range plus margin).
function defense.nearby_launchers(surface_state, force_index, position, margin)
  local result = {}
  for _, list in ipairs(abm_launchers(surface_state)) do
    for _, launcher in pairs(list) do
      if launcher.valid and launcher.force.index == force_index
        and defense_math.distance(launcher_position(launcher), position) <= defense.launcher_range(launcher) + margin then
        result[#result + 1] = launcher
      end
    end
  end
  return result
end

-- launchers: optional pre-filtered candidates (see nearby_launchers).
function defense.try_intercepts(missile, surface_state, launchers)
  if missile.intercepted or missile.finished then
    return true
  end
  local target = {id = missile.id, position = missile.position, class = missile.class}
  local lists = launchers and {launchers} or abm_launchers(surface_state)
  for _, list in ipairs(lists) do
    for _, launcher in pairs(list) do
      if launcher.valid and launcher.force.index == missile.force_index
        and defense.get_mode(launcher) ~= "drones" then
        try_intercept(launcher, target, surface_state)
      end
    end
  end
  return false
end

local function ballistic_in_range(launcher, surface_state)
  local range = defense.launcher_range(launcher)
  for _, missile in pairs(surface_state.active_missiles) do
    if not missile.intercepted and not missile.finished and missile.force_index == launcher.force.index
      and defense_math.distance(launcher_position(launcher), missile.position) <= range then
      return true
    end
  end
  return false
end

local function hostile(force, entity)
  return entity.force.index ~= force.index and not force.get_friend(entity.force)
    and not force.get_cease_fire(entity.force)
end

-- Strike, heavy and decoy drones look alike on radar; reconnaissance
-- aircraft are left to guns.
local function eligible_drone(launcher, record, range)
  local entity = record and record.entity
  return record ~= nil and DRONE_TARGET_KINDS[record.kind] and entity ~= nil and entity.valid
    and record.target_force_index == launcher.force.index and hostile(launcher.force, entity)
    and defense_math.distance(launcher_position(launcher), entity.position) <= range
end

local function choose_drone(surface_state, launcher, limit)
  local range = defense.launcher_range(launcher)
  local lock = surface_state.battery_tracking[launcher.unit_number]
  local previous = lock and lock.target_drone
  if previous and previous.valid then
    local record = surface_state.active_drones[previous.unit_number]
    if eligible_drone(launcher, record, range) then
      return previous
    end
  end
  if lock and lock.target_drone then
    surface_state.battery_tracking[launcher.unit_number] = nil
  end
  local nearest, nearest_distance, nearest_id
  for id, candidate in pairs(surface_state.active_drones) do
    if eligible_drone(launcher, candidate, range)
      and ordnance.engaged(surface_state, "d" .. id) < limit then
      local distance = defense_math.distance(launcher_position(launcher), candidate.entity.position)
      if not nearest or distance < nearest_distance or (distance == nearest_distance and id < nearest_id) then
        nearest, nearest_distance, nearest_id = candidate.entity, distance, id
      end
    end
  end
  return nearest
end

-- AA wagons: a gun mount on a rail car, aimed and fired by script.
local function update_aa_wagon(surface_state, wagon, tick, accuracy)
  local record = wagon_record(surface_state, wagon)
  local target
  local target_record = record.target_unit and surface_state.active_drones[record.target_unit]
  if target_record and target_record.entity.valid and hostile(wagon.force, target_record.entity)
    and defense_math.distance(wagon.position, target_record.entity.position) <= rules.AA_WAGON_RANGE then
    target = target_record.entity
  else
    record.target_unit = nil
    local best_distance
    for unit, candidate in pairs(surface_state.active_drones) do
      local entity = candidate.entity
      if entity and entity.valid and hostile(wagon.force, entity) then
        local distance = defense_math.distance(wagon.position, entity.position)
        if distance <= rules.AA_WAGON_RANGE and (not best_distance or distance < best_distance) then
          target, best_distance, record.target_unit = entity, distance, unit
        end
      end
    end
  end
  if not target then
    local loaded = record.flak_rounds > 0 or item_count(wagon, FLAK_MAGAZINE) > 0
    record.status = loaded and "ready" or "no-ammo"
    return
  end
  local desired = flight_math.orientation(wagon.position, target.position)
  local difference = (desired - record.heading + 0.5) % 1 - 0.5
  local step = rules.AA_WAGON_TURN_RATE * 6
  set_heading(surface_state, wagon, (record.heading + math.max(-step, math.min(step, difference))) % 1)
  if math.abs(difference) > step or tick < record.next_shot then
    return
  end
  if record.flak_rounds <= 0 then
    if not consume(wagon, FLAK_MAGAZINE) then
      record.status = "no-ammo"
      return
    end
    record.flak_rounds = rules.FLAK_MAGAZINE_ROUNDS
  end
  record.flak_rounds = record.flak_rounds - 1
  record.next_shot = tick + rules.AA_WAGON_COOLDOWN
  record.status = "engaging-drone"
  surface_state.counters.flak_shots = surface_state.counters.flak_shots + 1
  ordnance.launch_flak(surface_state, wagon, target, accuracy)
  audio.play(wagon.surface, "shahed-attack-flak-shot", wagon.position, "aa-wagon::" .. wagon.unit_number, 0)
end

function defense.update_drone_intercepts(tick)
  if tick % 6 ~= 0 then
    return
  end
  local limit = config.global("shahed-attack-interceptors-per-target")
  local flak_accuracy = config.global("shahed-attack-flak-accuracy")
  for _, surface_state in pairs(state.root().surfaces) do
    if next(surface_state.active_drones) then
      for _, list in ipairs(abm_launchers(surface_state)) do
        for _, launcher in pairs(list) do
          if launcher.valid then
            local mode = defense.get_mode(launcher)
            if (mode == "drones" or mode == "both")
              and not (mode == "both" and ballistic_in_range(launcher, surface_state)) then
              local drone = choose_drone(surface_state, launcher, limit)
              if drone then
                try_intercept(launcher, {drone = drone, position = drone.position}, surface_state)
              end
            end
          end
        end
      end
      for _, wagon in pairs(surface_state.defenses.aa_wagons) do
        if wagon.valid then
          update_aa_wagon(surface_state, wagon, tick, flak_accuracy)
        end
      end
    end
  end
end

function defense.on_script_trigger_effect(event)
  if event.effect_id ~= "shahed-attack-flak-shot" then
    return
  end
  local source = event.source_entity
  local target = event.target_entity
  if not source or not source.valid or not target or not target.valid then
    return
  end
  local surface_state = state.ensure_surface(source.surface)
  if not surface_state then
    return
  end
  surface_state.counters.flak_shots = surface_state.counters.flak_shots + 1
  ordnance.launch_flak(surface_state, source, target, config.global("shahed-attack-flak-accuracy"))
end

-- Once per second: battery status diodes, magazine reloads and wagon heads.
function defense.update(tick)
  for _, surface_state in pairs(state.root().surfaces) do
    for unit_number, lock in pairs(surface_state.battery_tracking) do
      if not lock.battery or not lock.battery.valid then surface_state.battery_tracking[unit_number] = nil end
    end
    for _, battery in pairs(surface_state.defenses.abm_batteries) do
      if battery.valid then
        local status = defense.launcher_status(battery)
        show_status(battery, status.key, STATUS_COLORS[status.key])
      end
    end
    for _, list in ipairs({surface_state.defenses.aa_wagons, surface_state.defenses.abm_wagons}) do
      for _, wagon in pairs(list) do
        if wagon.valid then ensure_wagon_head(surface_state, wagon) end
      end
    end
    -- Destruction events arrive a tick later; drop per-launcher state of
    -- launchers that are already gone.
    for _, map in ipairs({surface_state.battery_modes, surface_state.launcher_rounds, surface_state.battery_next_shot}) do
      for unit in pairs(map) do
        local launcher = surface_state.defenses.abm_batteries[unit] or surface_state.defenses.abm_wagons[unit]
        if not (launcher and launcher.valid) then map[unit] = nil end
      end
    end
  end
end

function defense.wagon_status(wagon)
  local surface_state = state.get_surface(wagon.surface.index)
  local record = surface_state and surface_state.wagon_state[wagon.unit_number]
  local magazines = item_count(wagon, FLAK_MAGAZINE)
  return {
    key = record and record.status or (magazines > 0 and "ready" or "no-ammo"),
    rounds = (record and record.flak_rounds or 0) + magazines * rules.FLAK_MAGAZINE_ROUNDS
  }
end

return defense
