-- Drone raids. A raid is planned as one event split into groups of up to
-- eight aircraft. Groups leave real airfields a little apart in time and
-- swing out to approach from different bearings, then converge on the target.
local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local balance = require("scripts.balance")
local config = require("scripts.lib.config")
local defense = require("scripts.defense")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local forces = require("scripts.forces")
local infrastructure = require("scripts.infrastructure")
local radar_signals = require("scripts.radar_signals")
local random = require("scripts.lib.random")
local rules = require("scripts.lib.air_rules")
local state = require("scripts.state")
local targeting = require("scripts.targeting")

local raids = {}

local UNIT_NAMES = {
  recon = "shahed-attack-recon-drone",
  strike = "shahed-attack-strike-drone",
  heavy = "shahed-attack-heavy-drone",
  decoy = "shahed-attack-decoy-drone"
}
raids.UNIT_NAMES = UNIT_NAMES

-- Warheads: inner radius/damage, outer radius/damage.
local WARHEADS = {
  strike = {inner = 3, inner_damage = 140, outer = 8, outer_damage = 45, explosions = 3},
  heavy = {inner = 4.5, inner_damage = 320, outer = 11, outer_damage = 100, explosions = 5},
  decoy = {inner = 1.5, inner_damage = 10, outer = 2.5, outer_damage = 5, explosions = 0}
}

-- Approach bearings relative to the direct route, in radians.
local GROUP_BEARINGS = {0, 0.9, -0.9, 1.5, -1.5, 0.45, -0.45, 1.2, -1.2}
local MAX_LIFETIME_TICKS = 20 * 60 * 60
local ATTACK_RANGE = 24

local function command_drone(record)
  if not record.entity.valid then
    return
  end
  local commandable = record.entity.commandable
  if not commandable then
    return
  end
  if record.attack_target and record.attack_target.valid then
    commandable.set_command({type = defines.command.attack, target = record.attack_target,
      distraction = defines.distraction.none})
    record.last_command_tick = game.tick
    return
  end
  local destination = record.target_position
  local radius = 0.75
  if record.mission == "returning" then
    destination = record.origin
    radius = 3
  elseif record.mission == "scanning" and record.orbit_destination then
    destination = record.orbit_destination
    radius = 1.5
  elseif record.mission == "approach" and record.via then
    destination = record.via
    radius = 6
  elseif record.mission == "approach" and record.approach_destination then
    destination = record.approach_destination
    radius = 2
  end
  -- Keep native pathfinding local: long commands across unknown chunks can
  -- send otherwise collisionless units away from their flight corridor.
  local position = record.entity.position
  local distance = defense_math.distance(position, destination)
  if distance > 64 then
    local direction = flight_math.normalized_motion(position, destination, record.entity.orientation)
    destination = flight_math.project_forward(position, direction, 64, 0)
    radius = 2
  end
  local surface = record.entity.surface
  local ready = true
  local steps = math.max(1, math.ceil(defense_math.distance(position, destination) / 16))
  for step = 1, steps do
    local point = flight_math.lerp_clamped(position, destination, step, steps)
    local chunk = {x = math.floor(point.x / 32), y = math.floor(point.y / 32)}
    if not surface.is_chunk_generated(chunk) then
      surface.request_to_generate_chunks(point, 1)
      ready = false
    end
  end
  if not ready then
    commandable.set_command({type = defines.command.stop, distraction = defines.distraction.none})
    record.navigation_waiting = true
    record.last_command_tick = game.tick
    return
  end
  record.navigation_waiting = false
  -- Request a small forward corridor asynchronously before the next waypoint.
  if distance > 32 then surface.request_to_generate_chunks(destination, 1) end
  commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = radius,
    distraction = defines.distraction.none
  })
  record.last_command_tick = game.tick
end

local function rotate(vector, angle)
  local cosine, sine = math.cos(angle), math.sin(angle)
  return {x = vector.x * cosine - vector.y * sine, y = vector.x * sine + vector.y * cosine}
end

local function active_drone_count(surface_state)
  local count = 0
  for _ in pairs(surface_state.active_drones) do count = count + 1 end
  return count
end

local function pick_sources(surface_state, target_position, options, generator)
  if options.sources and #options.sources > 0 then
    return options.sources
  end
  if options.source and options.source.valid then
    return {options.source}
  end
  local candidates = infrastructure.sources_in_range(surface_state, "airfields", target_position)
  if #candidates == 0 then
    return {}
  end
  -- The nearest airfield leads; others in range join large raids.
  if #candidates > 1 and generator:next_float() < 0.25 then
    local index = generator:range_int(1, #candidates)
    candidates[1], candidates[index] = candidates[index], candidates[1]
  end
  return candidates
end

-- Spawns one group of a planned raid.
local function spawn_group(surface, surface_state, group, generator)
  local force = game.forces[group.force_index]
  local target_entity = group.target
  if not force then
    return 0
  end
  if not (target_entity and target_entity.valid) then
    target_entity = targeting.choose(surface, force, generator, true)
    if not target_entity then return 0 end
  end
  local source = group.source
  if not (source and source.valid) then
    source = infrastructure.get_source(surface_state, "airfields", target_entity.position, generator)
    if not source then return 0 end
  end
  local cap = config.global("shahed-attack-max-active-drones")
  local count = math.min(group.count, cap - active_drone_count(surface_state))
  if count <= 0 then
    return 0
  end
  local evolution = game.forces.enemy.get_evolution_factor(surface)
  local origin = {x = source.position.x, y = source.position.y}
  local target_center = target_entity.position
  local route_distance = defense_math.distance(origin, target_center)
  local direction = flight_math.normalized_motion(origin, target_center, 0)
  local right = {x = -direction.y, y = direction.x}
  local columns = math.min(4, math.ceil(math.sqrt(count)))
  local lateral_spacing = generator:range_float(14, 18)
  local depth_spacing = generator:range_float(10, 14)

  -- Swing wide groups out so they arrive from another bearing.
  local via
  if group.bearing ~= 0 and route_distance > 160 then
    local back = {x = -direction.x, y = -direction.y}
    local swing = rotate(back, group.bearing)
    local reach = math.min(route_distance * 0.55, 600)
    via = {x = target_center.x + swing.x * reach, y = target_center.y + swing.y * reach}
  end
  local arrival_direction = via and flight_math.normalized_motion(via, target_center, 0) or direction
  local arrival_right = {x = -arrival_direction.y, y = arrival_direction.x}

  local used = {[target_entity.unit_number] = true}
  local suppression = balance.suppression_share(evolution, config.global("shahed-attack-defense-suppression-enabled"))
  local defenses = suppression > 0 and targeting.find_defenses(surface, force, target_center, 150) or {}
  local defense_cursor = 0
  local decoys_enabled = config.global("shahed-attack-decoys-enabled")
  local created = 0
  for local_slot = 1, count do
    local slot = group.slot_start + local_slot - 1
    local kind = group.forced_kind or balance.drone_kind(group.event_kind, slot, evolution,
      generator:next_float(), decoys_enabled)
    local slot_target = target_entity
    local mission_role = "strike"
    if (kind == "strike" or kind == "heavy") and #defenses > 0 and generator:next_float() < suppression then
      defense_cursor = defense_cursor % #defenses + 1
      local candidate = defenses[defense_cursor]
      if candidate.valid then
        slot_target = candidate
        mission_role = "suppression"
      end
    elseif local_slot > 1 then
      local distinct = targeting.choose_distinct_near_position(surface, force, target_center, 96, used, generator)
      if distinct then
        slot_target = distinct
        used[distinct.unit_number] = true
      end
    end
    local column = (local_slot - 1) % columns
    local row = math.floor((local_slot - 1) / columns)
    local lateral = (column - (columns - 1) / 2) * lateral_spacing
    local depth = -row * depth_spacing
    local spawn = {
      x = origin.x + right.x * lateral + direction.x * depth + generator:range_float(-1, 1),
      y = origin.y + right.y * lateral + direction.y * depth + generator:range_float(-1, 1)
    }
    local approach_destination
    if route_distance >= 80 then
      approach_destination = {
        x = slot_target.position.x + arrival_right.x * lateral + arrival_direction.x * (depth - 48),
        y = slot_target.position.y + arrival_right.y * lateral + arrival_direction.y * (depth - 48)
      }
    end
    local entity = surface.create_entity({name = UNIT_NAMES[kind], position = spawn, force = forces.get()})
    if entity then
      local record = {
        entity = entity,
        event_id = group.event_id,
        event_size = group.event_size,
        kind = kind,
        role = mission_role,
        mission = "approach",
        origin = origin,
        source = source,
        source_unit_number = source.unit_number,
        target_entity = slot_target,
        target_force_index = group.force_index,
        target_position = {x = slot_target.position.x, y = slot_target.position.y},
        via = via and {x = via.x + right.x * lateral, y = via.y + right.y * lateral} or nil,
        approach_destination = approach_destination,
        spawn_tick = game.tick,
        scan_required = generator:range_int(1200, 1800),
        scan_progress = 0,
        last_position = {x = entity.position.x, y = entity.position.y},
        orbit_center = {x = slot_target.position.x, y = slot_target.position.y},
        orbit_radius_x = generator:range_float(18, 30),
        orbit_radius_y = generator:range_float(12, 22),
        orbit_phase = generator:range_float(0, math.pi * 2),
        orbit_direction = generator:next_float() < 0.5 and -1 or 1,
        orbit_index = 0,
        orbit_waypoints = 12
      }
      surface_state.active_drones[entity.unit_number] = record
      command_drone(record)
      created = created + 1
      surface_state.counters.drones_launched = surface_state.counters.drones_launched + 1
      if kind == "decoy" then
        surface_state.counters.decoys_launched = surface_state.counters.decoys_launched + 1
      end
    end
  end
  return created
end

-- Plans and launches a raid from real airfields.
-- options: source | sources, generator, stagger (default true), forced_kind.
function raids.spawn_event(surface, target_force, target_entity, event_kind, size, options)
  options = options or {}
  if not surface or not target_force or not target_entity or not target_entity.valid then
    return nil, "missing-target"
  end
  local surface_state = state.ensure_surface(surface)
  if not surface_state then
    return nil, "unsupported-surface"
  end
  local generator = options.generator or random.new(surface_state.rng_state)
  local sources = pick_sources(surface_state, target_entity.position, options, generator)
  if #sources == 0 then
    return nil, "no-source"
  end
  local requested = math.floor(tonumber(size) or 2)
  local maximum = config.global("shahed-attack-max-raid-size")
  local actual_size = event_kind == "recon" and math.min(math.max(requested, 1), 2)
    or math.min(math.max(requested, 2), maximum)
  local cap = config.global("shahed-attack-max-active-drones")
  local available = cap - active_drone_count(surface_state)
  if available <= 0 then
    return nil, "drone-limit"
  end
  actual_size = math.min(actual_size, available)

  local event_id = state.next_event_id()
  local groups = event_kind == "recon" and 1 or balance.group_count(actual_size)
  local per_group = math.floor(actual_size / groups)
  local remainder = actual_size - per_group * groups
  local slot = 1
  local delay = 0
  local created = 0
  for index = 1, groups do
    local count = per_group + (index <= remainder and 1 or 0)
    local group = {
      event_id = event_id,
      event_size = actual_size,
      event_kind = event_kind,
      forced_kind = options.forced_kind,
      slot_start = slot,
      count = count,
      source = sources[(index - 1) % #sources + 1],
      target = target_entity,
      force_index = target_force.index,
      bearing = GROUP_BEARINGS[(index - 1) % #GROUP_BEARINGS + 1]
    }
    slot = slot + count
    if index == 1 or options.stagger == false then
      created = created + spawn_group(surface, surface_state, group, generator)
    else
      delay = delay + generator:range_int(15 * 60, 45 * 60)
      local id = state.next_event_id()
      surface_state.pending_events[id] = {tick = game.tick + delay, kind = "drone-group",
        event_id = event_id, group = group}
      created = created + count
    end
  end
  surface_state.rng_state = generator.state
  if created == 0 then
    return nil, "spawn-failed"
  end
  surface_state.counters.events = surface_state.counters.events + 1
  if event_kind == "recon" then
    surface_state.counters.recon = surface_state.counters.recon + 1
  else
    surface_state.counters.raids = surface_state.counters.raids + 1
  end
  return event_id
end

function raids.launch_pending_group(surface, surface_state, pending, generator)
  return spawn_group(surface, surface_state, pending.group, generator)
end

local function next_orbit_destination(record)
  record.orbit_index = record.orbit_index + record.orbit_direction
  local angle = record.orbit_phase + record.orbit_index * (math.pi * 2 / record.orbit_waypoints)
  record.orbit_destination = flight_math.orbit_point(record.orbit_center, record.orbit_radius_x,
    record.orbit_radius_y, angle)
  command_drone(record)
end

local function damage_entities(surface, target_force, position, warhead, cause)
  local multiplier = config.global("shahed-attack-damage-multiplier")
  local attacker = forces.get()
  local victims = surface.find_entities_filtered({position = position, radius = warhead.outer, force = target_force})
  for _, victim in ipairs(victims) do
    if victim.valid and victim.health then
      local distance = defense_math.distance(position, victim.position)
      local damage = distance <= warhead.inner and warhead.inner_damage or warhead.outer_damage
      victim.damage(damage * multiplier, attacker, "explosion", cause, cause)
    end
  end
end

local function remove_record(surface_state, record)
  if record and record.entity and record.entity.unit_number then
    surface_state.active_drones[record.entity.unit_number] = nil
  end
end

function raids.detonate(record, heavy)
  if not record or not record.entity or not record.entity.valid then
    return
  end
  local entity = record.entity
  local surface = entity.surface
  local surface_state = state.get_surface(surface.index)
  local position = {x = entity.position.x, y = entity.position.y}
  local force = game.forces[record.target_force_index]
  local kind = record.kind == "decoy" and "decoy" or (heavy and "heavy" or "strike")
  local warhead = WARHEADS[kind]
  remove_record(surface_state, record)
  if kind == "decoy" then
    -- Decoys carry no real warhead: a small pop and a scorch mark.
    surface.create_entity({name = "explosion", position = position})
  else
    surface_state.counters.drone_impacts = surface_state.counters.drone_impacts + 1
    audio.play(surface, heavy and "shahed-attack-heavy-impact" or "shahed-attack-drone-impact",
      position, "drone-impact::" .. record.event_id, 1)
    surface.create_entity({name = "big-explosion", position = position})
    surface.create_entity({name = heavy and "big-scorchmark" or "medium-scorchmark", position = position})
    for index = 1, warhead.explosions do
      local angle = index * math.pi * 2 / warhead.explosions
      local distance = heavy and 3 or 2
      surface.create_entity({
        name = heavy and "big-explosion" or "medium-explosion",
        position = {x = position.x + math.cos(angle) * distance, y = position.y + math.sin(angle) * distance}
      })
    end
    for index = 1, heavy and 4 or 2 do
      surface.create_entity({
        name = "fire-flame",
        position = {x = position.x + (index % 3) - 1, y = position.y + math.floor(index / 3) - 1},
        force = forces.get()
      })
    end
  end
  if force then
    damage_entities(surface, force, position, warhead, entity)
  end
  entity.destroy()
end

local function maybe_play_flyby(record)
  if not record.entity or not record.entity.valid then
    return
  end
  for _, player in pairs(game.connected_players) do
    if player.surface.index == record.entity.surface.index then
      local distance = defense_math.distance(player.position, record.entity.position)
      if distance >= 8 and distance <= 28 and audio.mark_flyby(record, player.index) then
        audio.play(record.entity.surface, "shahed-attack-drone-flyby", record.entity.position,
          "flyby::" .. player.index .. "::" .. record.event_id, 3600)
      end
    end
  end
end

local function retarget(record, generator)
  local force = game.forces[record.target_force_index]
  if not force or not record.entity.valid then
    return false
  end
  local target = targeting.choose_near_position(record.entity.surface, force, record.target_position, 64)
    or targeting.choose(record.entity.surface, force, generator, false)
  if not target then
    return false
  end
  record.target_entity = target
  record.target_position = {x = target.position.x, y = target.position.y}
  record.orbit_center = {x = target.position.x, y = target.position.y}
  record.orbit_destination = nil
  record.approach_destination = nil
  record.attack_target = nil
  record.mission = "approach"
  command_drone(record)
  return true
end

local function continue_after_target_loss(record, generator)
  if retarget(record, generator) then
    return
  end
  record.target_entity = nil
  record.attack_target = nil
  record.mission = record.kind == "recon" and "returning" or "terminal"
  command_drone(record)
end

local function finish_recon(surface_state, record)
  surface_state.intelligence[record.target_force_index] = math.max(
    surface_state.intelligence[record.target_force_index] or 0, 2)
  local force = game.forces[record.target_force_index]
  if force then
    alerts.recon_complete(force, record.target_entity)
  end
  record.mission = "returning"
  command_drone(record)
end

local function maybe_alert(surface_state, record, distance_to_target)
  if surface_state.alerted_events[record.event_id] then
    return
  end
  local tracking = defense.tracking_for_position(surface_state, record.target_force_index, record.entity.position)
  if rules.drone_warning(distance_to_target, record.entity.speed, tracking > 0) then
    surface_state.alerted_events[record.event_id] = true
    local eta = rules.drone_eta(distance_to_target, record.entity.speed)
    local direction = rules.incoming_direction(record.entity.position, record.target_position)
    surface_state.warning_history[record.event_id] = {kind = "air-raid", tick = game.tick,
      eta = eta, direction = direction, position = record.entity.position, target = record.target_position}
    radar_signals.record_detection(record.entity.surface, record.target_force_index, record.entity.position, "air", game.tick)
    local force = game.forces[record.target_force_index]
    if force then
      alerts.air_raid(force,
        record.target_entity and record.target_entity.valid and record.target_entity or record.entity,
        record.event_size, {"shahed-attack-direction." .. direction}, record.event_id, math.ceil(eta))
    end
  end
end

-- Trains move: follow the target and switch to a direct attack when close.
local function track_moving_target(record, distance)
  local target = record.target_entity
  if not targeting.is_rolling_stock(target) then
    return
  end
  record.target_position = {x = target.position.x, y = target.position.y}
  if distance <= ATTACK_RANGE then
    if record.attack_target ~= target then
      record.attack_target = target
      record.via = nil
      record.approach_destination = nil
      command_drone(record)
    end
  elseif record.attack_target then
    record.attack_target = nil
    command_drone(record)
  end
end

local function update_record(surface_state, record, tick, generator)
  if not record.entity or not record.entity.valid then
    return false
  end
  if tick - record.spawn_tick > MAX_LIFETIME_TICKS then
    record.entity.destroy()
    return false
  end

  local current_position = {x = record.entity.position.x, y = record.entity.position.y}
  record.last_motion = flight_math.normalized_motion(record.last_position or current_position,
    current_position, record.entity.orientation)
  record.last_position = current_position

  -- Unit commands can be dropped after nearby explosions or transient
  -- pathfinder failures. Reassert the flight plan periodically.
  if record.navigation_waiting or tick - (record.last_command_tick or record.spawn_tick) >= 180 then
    command_drone(record)
  end

  if record.mission == "returning" then
    if defense_math.distance(record.entity.position, record.origin) <= 5 then
      record.entity.destroy()
      return false
    end
    return true
  end

  if record.mission ~= "terminal" and (not record.target_entity or not record.target_entity.valid) then
    continue_after_target_loss(record, generator)
  end

  if record.mission == "approach" and record.via
    and defense_math.distance(record.entity.position, record.via) <= 8 then
    record.via = nil
    command_drone(record)
  end
  if record.mission == "approach" and not record.via and record.approach_destination
    and defense_math.distance(record.entity.position, record.approach_destination) <= 3 then
    record.approach_destination = nil
    command_drone(record)
  end

  local distance_to_target = defense_math.distance(record.entity.position, record.target_position)
  if record.kind ~= "recon" and record.target_entity and record.target_entity.valid then
    track_moving_target(record, defense_math.distance(record.entity.position, record.target_entity.position))
    distance_to_target = defense_math.distance(record.entity.position, record.target_position)
  end
  maybe_alert(surface_state, record, distance_to_target)

  if record.kind == "recon" then
    if record.mission == "approach" and distance_to_target <= 18 then
      record.mission = "scanning"
      record.via = nil
      record.orbit_center = {x = record.target_position.x, y = record.target_position.y}
      next_orbit_destination(record)
    elseif record.mission == "scanning" then
      record.scan_progress = record.scan_progress + 60
      if not record.orbit_destination
        or defense_math.distance(record.entity.position, record.orbit_destination) <= 4 then
        next_orbit_destination(record)
      end
      if record.scan_progress >= record.scan_required then
        finish_recon(surface_state, record)
      end
    end
  elseif distance_to_target <= 3 then
    raids.detonate(record, record.kind == "heavy")
    return false
  end
  return true
end

function raids.update(tick)
  for _, surface_state in pairs(storage.shahed_attack.surfaces) do
    if next(surface_state.active_drones) then
      local generator = random.new(surface_state.rng_state)
      for unit_number, record in pairs(surface_state.active_drones) do
        maybe_play_flyby(record)
        if not update_record(surface_state, record, tick, generator) then
          surface_state.active_drones[unit_number] = nil
        end
      end
      surface_state.rng_state = generator.state
    end
  end
end

function raids.on_script_trigger_effect(event)
  local wreck_outcome = event.effect_id and event.effect_id:match("^shahed%-attack%-wreck%-completed%-(%a+)$")
  if wreck_outcome == "safe" or wreck_outcome == "fuel" or wreck_outcome == "warhead" then
    local event_surface = event.surface_index and game.get_surface(event.surface_index) or nil
    if not event_surface and event.source_entity and event.source_entity.valid then
      event_surface = event.source_entity.surface
    end
    local surface_state = event_surface and state.ensure_surface(event_surface)
    if surface_state then
      local counter = "wreck_" .. wreck_outcome
      surface_state.counters[counter] = (surface_state.counters[counter] or 0) + 1
    end
    return
  end
  local source = event.source_entity
  if not source or not source.valid or not source.unit_number then
    return
  end
  local surface_state = state.get_surface(source.surface.index)
  local record = surface_state and surface_state.active_drones[source.unit_number]
  if not record then
    return
  end
  if event.effect_id == "shahed-attack-strike-impact" or event.effect_id == "shahed-attack-decoy-impact" then
    raids.detonate(record, false)
  elseif event.effect_id == "shahed-attack-heavy-impact" then
    raids.detonate(record, true)
  end
end

function raids.on_entity_died(event)
  local entity = event.entity
  if not entity or not entity.unit_number then
    return
  end
  local surface_state = state.get_surface(entity.surface.index)
  local record = surface_state and surface_state.active_drones[entity.unit_number]
  if not record then
    return
  end
  surface_state.active_drones[entity.unit_number] = nil
  surface_state.counters.drones_destroyed = surface_state.counters.drones_destroyed + 1
  local generator = random.new(surface_state.rng_state)
  local evolution = game.forces.enemy.get_evolution_factor(entity.surface)
  local outcome = balance.crash_outcome(record.kind, generator:next_float(), evolution)
  local position = {x = entity.position.x, y = entity.position.y}
  local direction = record.last_motion or flight_math.normalized_motion(
    record.last_position or position, position, entity.orientation)
  local distance = generator:range_float(8, 14)
  local deviation = generator:range_float(-math.pi / 12, math.pi / 12)
  local target_position = flight_math.project_forward(position, direction, distance, deviation)
  local direction_index = flight_math.direction_index(direction, 8)
  surface_state.rng_state = generator.state
  local wreck = entity.surface.create_entity({
    name = (record.kind == "recon" and "shahed-attack-falling-recon-wreck-" or "shahed-attack-falling-wreck-")
      .. outcome .. "-" .. direction_index,
    position = position,
    force = forces.get(),
    target = target_position,
    speed = distance / 90
  })
  if not wreck then
    log("Shahed Attack: failed to create falling wreck projectile")
  end
end

-- Remove all drones and queued groups without effects (admin cleanup).
function raids.clear(surface_state)
  local count = 0
  for unit_number, record in pairs(surface_state.active_drones) do
    if record.entity and record.entity.valid then record.entity.destroy() end
    surface_state.active_drones[unit_number] = nil
    count = count + 1
  end
  for id, pending in pairs(surface_state.pending_events) do
    if pending.kind == "drone-group" then
      surface_state.pending_events[id] = nil
      count = count + pending.group.count
    end
  end
  return count
end

return raids
