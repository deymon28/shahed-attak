local audio = require("scripts.audio")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local state = require("scripts.state")

local rules = require("scripts.lib.air_rules")
local ordnance = require("scripts.ordnance")

local defense = {}

local function setting(name, fallback)
  local value = settings.global[name]
  return value and value.value or fallback
end

local DEFENSE_NAMES = {
  ["shahed-attack-early-warning-radar"] = "radars",
  ["shahed-attack-aa-turret"] = "aa_turrets",
  ["shahed-attack-abm-battery"] = "abm_batteries"
}

local function root()
  storage.shahed_attack.defense_registrations = storage.shahed_attack.defense_registrations or {}
  return storage.shahed_attack
end

function defense.get_mode(battery)
  local surface_state = state.get_surface(battery.surface.index)
  local mode = surface_state and surface_state.battery_modes and surface_state.battery_modes[battery.unit_number]
  return (mode == "both" or mode == "drones") and mode or "ballistic"
end

function defense.set_mode(battery, mode)
  if not battery or not battery.valid or battery.name ~= "shahed-attack-abm-battery"
    or (mode ~= "ballistic" and mode ~= "both" and mode ~= "drones") then return false end
  local surface_state = state.get_surface(battery.surface.index)
  if not surface_state then return false end
  if defense.get_mode(battery) ~= mode then
    surface_state.battery_modes = surface_state.battery_modes or {}
    surface_state.battery_modes[battery.unit_number] = mode ~= "ballistic" and mode or nil
    if surface_state.battery_tracking then surface_state.battery_tracking[battery.unit_number] = nil end
  end
  return true
end

local function register(entity, defense_type)
  local surface_state = state.ensure_surface(entity.surface)
  local list = surface_state.defenses[defense_type]
  for _, existing in pairs(list) do
    if existing and existing.valid and existing.unit_number == entity.unit_number then
      return
    end
  end
  local index = #list + 1
  list[index] = entity
  local registration = script.register_on_object_destroyed(entity)
  root().defense_registrations[registration] = {
    surface_index = entity.surface.index,
    unit_number = entity.unit_number,
    defense_type = defense_type,
    index = index
  }
end

function defense.initialize()
  root()
  for _, surface in pairs(game.surfaces) do
    for name, defense_type in pairs(DEFENSE_NAMES) do
      for _, entity in ipairs(surface.find_entities_filtered({name = name})) do
        register(entity, defense_type)
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
  local data = root()
  local record = data.defense_registrations[event.registration_number]
  if not record then
    return
  end
  data.defense_registrations[event.registration_number] = nil
  local surface_state = state.get_surface(record.surface_index)
  if surface_state and surface_state.defenses[record.defense_type] then
    surface_state.defenses[record.defense_type][record.index] = false
    if record.unit_number and surface_state.battery_modes then
      surface_state.battery_modes[record.unit_number] = nil
    end
  end
end

local function powered(entity, required_energy)
  return entity.valid and entity.energy >= (required_energy or 1000)
end

function defense.tracking_for_position(surface_state, force_index, position, threat_kind)
  local range = threat_kind == "ballistic" and rules.BALLISTIC_RADAR_RANGE or rules.DRONE_RADAR_RANGE
  local best = 0
  for _, radar in pairs(surface_state.defenses.radars or {}) do
    if radar and radar.valid and radar.force.index == force_index and powered(radar, 1000) then
      local distance = defense_math.distance(radar.position, position)
      if distance <= range then
        best = math.max(best, math.max(0.01, 1 - distance / range))
      end
    end
  end
  return best
end

local function consume_interceptor(battery)
  local inventory = battery.get_inventory(defines.inventory.turret_ammo)
  if not inventory or inventory.get_item_count("shahed-attack-interceptor") < 1 then
    return false
  end
  return inventory.remove({name = "shahed-attack-interceptor", count = 1}) == 1
end

local function status(battery, key, color)
  battery.custom_status = {diode=defines.entity_status_diode[color or "green"], label={"shahed-attack-status."..key}}
end

local function aim_at(battery, missile, surface_state)
  local tracking = surface_state.battery_tracking
  local lock = tracking[battery.unit_number]
  if lock and (lock.missile_id ~= missile.id or lock.target_drone ~= missile.drone) then
    local previous = lock.missile_id and (surface_state.active_missiles or {})[lock.missile_id]
    if lock.target_drone and lock.target_drone.valid and missile.drone then previous = lock.target_drone end
    if previous and not (lock.missile_id and (previous.intercepted or previous.finished))
      and defense_math.distance(battery.position, previous.position) <= rules.ABM_RANGE then
      return false
    end
    lock = nil
  end
  if not lock then
    lock = {battery=battery, missile_id=missile.id, target_drone=missile.drone,
      acquired_tick=game.tick, updated_tick=game.tick}
    tracking[battery.unit_number] = lock
  end
  local desired = flight_math.orientation(battery.position, missile.position)
  local heading = battery.orientation or 0
  local difference = (desired - heading + 0.5) % 1 - 0.5
  local step = rules.ABM_TURN_RATE * math.max(0, game.tick - lock.updated_tick)
  battery.orientation = (heading + math.max(-step, math.min(step, difference))) % 1
  lock.updated_tick = game.tick
  return math.abs(difference) <= step + 0.000001
    and game.tick - lock.acquired_tick >= rules.ABM_AIM_TICKS
end

local function try_intercept(battery, missile, surface_state)
  local distance = defense_math.distance(battery.position, missile.position)
  local inventory = battery.get_inventory(defines.inventory.turret_ammo)
  local ammunition = inventory and inventory.get_item_count("shahed-attack-interceptor") or 0
  local next_tick = surface_state.battery_next_shot[battery.unit_number] or 0
  local ready_to_aim = distance <= rules.ABM_RANGE and ammunition > 0 and battery.energy >= rules.ABM_ENERGY
  local aimed = ready_to_aim and aim_at(battery, missile, surface_state)
  if not ready_to_aim then
    local lock = surface_state.battery_tracking[battery.unit_number]
    if lock and lock.missile_id == missile.id and lock.target_drone == missile.drone then
      surface_state.battery_tracking[battery.unit_number] = nil
    end
  end
  if rules.battery_ready(distance, game.tick, next_tick, battery.energy, ammunition)
    and aimed
    and consume_interceptor(battery) then
    battery.energy = battery.energy - rules.ABM_ENERGY
    surface_state.battery_next_shot[battery.unit_number] = game.tick + rules.ABM_COOLDOWN
    local accuracy = setting("shahed-attack-intercept-accuracy", rules.INTERCEPT_ACCURACY)
    ordnance.launch_interceptor(surface_state,battery,missile,accuracy)
    if missile.probabilities then missile.probabilities[#missile.probabilities+1] = accuracy end
    surface_state.counters.interceptor_launches = (surface_state.counters.interceptor_launches or 0) + 1
    audio.play(battery.surface,"shahed-attack-intercept-launch",battery.position,
      "intercept-launch::"..battery.unit_number,15)
    status(battery,missile.drone and "engaging-drone" or "engaging")
  elseif distance <= rules.ABM_RANGE then
    if ammunition == 0 then status(battery,"no-ammo","red")
    elseif battery.energy < rules.ABM_ENERGY then status(battery,"charging","yellow")
    elseif game.tick < next_tick then status(battery,"reloading","yellow")
    else status(battery,missile.drone and "engaging-drone" or "engaging") end
  end
end

function defense.try_intercepts(missile, surface_state)
  if missile.intercepted or missile.finished then return true end
  surface_state.battery_next_shot = surface_state.battery_next_shot or {}
  surface_state.battery_tracking = surface_state.battery_tracking or {}
  for _, battery in pairs(surface_state.defenses.abm_batteries or {}) do
    if battery and battery.valid and battery.force.index == missile.force_index
      and not (surface_state.battery_modes and surface_state.battery_modes[battery.unit_number] == "drones") then
      try_intercept(battery, missile, surface_state)
    end
  end
  return false
end

local function ballistic_in_range(battery, surface_state)
  for _, missile in pairs(surface_state.active_missiles or {}) do
    if not missile.intercepted and not missile.finished and missile.force_index == battery.force.index
      and defense_math.distance(battery.position, missile.position) <= rules.ABM_RANGE then return true end
  end
  return false
end

local function eligible_drone(battery, record)
  local entity = record and record.entity
  return record and (record.kind == "strike" or record.kind == "heavy") and entity and entity.valid
    and record.target_force_index == battery.force.index and entity.force.index ~= battery.force.index
    and not battery.force.get_friend(entity.force) and not battery.force.get_cease_fire(entity.force)
    and defense_math.distance(battery.position, entity.position) <= rules.ABM_RANGE
end

function defense.update_drone_intercepts(tick)
  if tick % 6 ~= 0 then return end
  for _, surface_state in pairs(storage.shahed_attack.surfaces) do
    for _, battery in pairs(surface_state.defenses.abm_batteries or {}) do
      local mode = battery and battery.valid and surface_state.battery_modes
        and surface_state.battery_modes[battery.unit_number]
      if (mode == "drones" or mode == "both")
        and not (mode == "both" and ballistic_in_range(battery, surface_state)) then
        surface_state.battery_next_shot = surface_state.battery_next_shot or {}
        surface_state.battery_tracking = surface_state.battery_tracking or {}
        local nearest, nearest_distance, nearest_id
        local lock = surface_state.battery_tracking[battery.unit_number]
        local previous = lock and lock.target_drone
        local record = previous and previous.valid and surface_state.active_drones[previous.unit_number]
        if eligible_drone(battery, record) then
          nearest = previous
        else
          if lock and lock.target_drone then surface_state.battery_tracking[battery.unit_number] = nil end
          for id, candidate in pairs(surface_state.active_drones or {}) do
            if eligible_drone(battery, candidate) then
              local distance = defense_math.distance(battery.position, candidate.entity.position)
              if not nearest or distance < nearest_distance or (distance == nearest_distance and id < nearest_id) then
                nearest, nearest_distance, nearest_id = candidate.entity, distance, id
              end
            end
          end
        end
        if nearest then try_intercept(battery, {drone=nearest, position=nearest.position}, surface_state) end
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
  local counters = surface_state.counters
  counters.flak_shots = (counters.flak_shots or 0) + 1
  ordnance.launch_flak(surface_state,source,target,setting("shahed-attack-flak-accuracy",0.62))
end

function defense.update(tick)
  for _, surface_state in pairs(storage.shahed_attack.surfaces) do
    local live_batteries = {}
    for unit_number, lock in pairs(surface_state.battery_tracking or {}) do
      if not lock.battery or not lock.battery.valid then surface_state.battery_tracking[unit_number] = nil end
    end
    for _, battery in pairs(surface_state.defenses.abm_batteries or {}) do
      if battery and battery.valid then
        live_batteries[battery.unit_number] = true
        local inventory = battery.get_inventory(defines.inventory.turret_ammo)
        if not inventory or inventory.get_item_count("shahed-attack-interceptor") == 0 then
          status(battery,"no-ammo","red")
        elseif battery.energy < rules.ABM_ENERGY then status(battery,"charging","yellow")
        elseif tick < (surface_state.battery_next_shot[battery.unit_number] or 0) then status(battery,"reloading","yellow")
        else status(battery,"ready") end
      end
    end
    for unit_number in pairs(surface_state.battery_modes or {}) do
      if not live_batteries[unit_number] then surface_state.battery_modes[unit_number] = nil end
    end
  end
end

return defense
