local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local balance = require("scripts.balance")
local defense = require("scripts.defense")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local forces = require("scripts.forces")
local infrastructure = require("scripts.infrastructure")
local random = require("scripts.lib.random")
local state = require("scripts.state")
local targeting = require("scripts.targeting")

local rules = require("scripts.lib.air_rules")
local radar_signals = require("scripts.radar_signals")

local raids = {}

local UNIT_NAMES = {
  recon = "shahed-attack-recon-drone",
  strike = "shahed-attack-strike-drone",
  heavy = "shahed-attack-heavy-drone"
}

local function setting(name, fallback)
  local value = settings.global[name]
  return value and value.value or fallback
end

local function command_drone(record)
  if not record.entity.valid then
    return
  end
  local commandable = record.entity.commandable
  if not commandable then
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
  local steps = math.max(1, math.ceil(defense_math.distance(position,destination)/16))
  for step=1,steps do
    local point = flight_math.lerp_clamped(position,destination,step,steps)
    local chunk = {x=math.floor(point.x/32), y=math.floor(point.y/32)}
    if not surface.is_chunk_generated(chunk) then
      surface.request_to_generate_chunks(point, 1)
      ready = false
    end
  end
  if not ready then
    commandable.set_command({type=defines.command.stop, distraction=defines.distraction.none})
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

local function resolve_origin(surface_state, target_position, generator, source_type, options)
  if options.origin_position then
    return {
      x = options.origin_position.x,
      y = options.origin_position.y
    }, nil
  end
  if options.source and options.source.valid then
    return {x=options.source.position.x,y=options.source.position.y},options.source
  end
  local force_external = options.force_external
  if not force_external then
    local source = infrastructure.get_source(surface_state, source_type, target_position, generator)
    if source and source.valid then
      return {x = source.position.x, y = source.position.y}, source
    end
  end
  return infrastructure.external_origin(target_position, generator, 240, 340), nil
end

local function drone_kind_for_slot(event_kind, evolution, generator, slot)
  if event_kind == "recon" then
    return "recon"
  end
  if event_kind == "mixed" and slot == 1 then
    return "recon"
  end
  local heavy_share = evolution >= 0.45 and math.min(0.30, (evolution - 0.45) * 0.55) or 0
  return generator:next_float() < heavy_share and "heavy" or "strike"
end

function raids.spawn_event(surface, target_force, target_entity, event_kind, size, options)
  options = options or {}
  if not surface or not target_force or not target_entity or not target_entity.valid then
    return nil, "missing-target"
  end
  local surface_state = state.ensure_surface(surface)
  local generator = options.generator or random.new(surface_state.rng_state)
  local evolution = game.forces.enemy.get_evolution_factor(surface)
  local origin, source = resolve_origin(
    surface_state,
    target_entity.position,
    generator,
    "airfields",
    options
  )
  local event_id = state.next_event_id()
  local requested_size = math.floor(tonumber(size) or 2)
  local actual_size = event_kind == "recon"
    and math.min(math.max(requested_size, 1), 2)
    or math.min(math.max(requested_size, 2), 12)
  local formation_columns = math.min(4, math.ceil(math.sqrt(actual_size)))
  local formation_direction = flight_math.normalized_motion(origin, target_entity.position, 0)
  local formation_right = {x = -formation_direction.y, y = formation_direction.x}
  local lateral_spacing = generator:range_float(14, 18)
  local depth_spacing = generator:range_float(10, 14)
  local used_targets = {}
  if target_entity.unit_number then
    used_targets[target_entity.unit_number] = true
  end

  local created = 0
  for slot = 1, actual_size do
    local kind = drone_kind_for_slot(event_kind, evolution, generator, slot)
    local slot_target = target_entity
    if slot > 1 then
      local distinct_target = targeting.choose_distinct_near_position(
        surface,
        target_force,
        target_entity.position,
        96,
        used_targets,
        generator
      )
      if distinct_target then
        slot_target = distinct_target
        used_targets[distinct_target.unit_number] = true
      end
    end
    local column = (slot - 1) % formation_columns
    local row = math.floor((slot - 1) / formation_columns)
    local lateral = (column - (formation_columns - 1) / 2) * lateral_spacing
    local depth = -row * depth_spacing
    local offset = {
      x = origin.x + formation_right.x * lateral + formation_direction.x * depth
        + generator:range_float(-1, 1),
      y = origin.y + formation_right.y * lateral + formation_direction.y * depth
        + generator:range_float(-1, 1)
    }
    local approach_destination
    if defense_math.distance(origin, target_entity.position) >= 80 then
      approach_destination = {
        x = target_entity.position.x + formation_right.x * lateral
          + formation_direction.x * (depth - 48),
        y = target_entity.position.y + formation_right.y * lateral
          + formation_direction.y * (depth - 48)
      }
    end
    local entity = surface.create_entity({name = UNIT_NAMES[kind], position = offset, force = forces.get()})
    if entity then
      local record = {
        entity = entity,
        event_id = event_id,
        event_size = actual_size,
        kind = kind,
        mission = "approach",
        origin = origin,
        source = source,
        source_unit_number = source and source.unit_number or nil,
        target_entity = slot_target,
        target_force_index = target_force.index,
        target_position = {x = slot_target.position.x, y = slot_target.position.y},
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

local function next_orbit_destination(record)
  record.orbit_index = record.orbit_index + record.orbit_direction
  local angle = record.orbit_phase
    + record.orbit_index * (math.pi * 2 / record.orbit_waypoints)
  record.orbit_destination = flight_math.orbit_point(
    record.orbit_center,
    record.orbit_radius_x,
    record.orbit_radius_y,
    angle
  )
  command_drone(record)
end

local function damage_entities(surface, target_force, position, inner_radius, outer_radius, inner_damage, outer_damage, cause)
  local multiplier = setting("shahed-attack-damage-multiplier", 1)
  local victims = surface.find_entities_filtered({position = position, radius = outer_radius, force = target_force})
  for _, victim in ipairs(victims) do
    if victim.valid and victim.health then
      local distance = defense_math.distance(position, victim.position)
      local damage = distance <= inner_radius and inner_damage or outer_damage
      victim.damage(damage * multiplier, forces.get(), "explosion", cause, cause)
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
  local surface_state = state.get_surface(entity.surface.index)
  local position = {x = entity.position.x, y = entity.position.y}
  local force = game.forces[record.target_force_index]
  remove_record(surface_state, record)
  audio.play(
    entity.surface,
    heavy and "shahed-attack-heavy-impact" or "shahed-attack-drone-impact",
    position,
    "drone-impact::" .. record.event_id,
    1
  )
  entity.surface.create_entity({name = "big-explosion", position = position})
  entity.surface.create_entity({
    name = heavy and "big-scorchmark" or "medium-scorchmark",
    position = position
  })
  local secondary_explosions = heavy and 5 or 3
  for index = 1, secondary_explosions do
    local angle = index * math.pi * 2 / secondary_explosions
    local distance = heavy and 3.5 or 2.3
    entity.surface.create_entity({
      name = heavy and "big-explosion" or "medium-explosion",
      position = {
        x = position.x + math.cos(angle) * distance,
        y = position.y + math.sin(angle) * distance
      }
    })
  end
  if force then
    if heavy then
      damage_entities(entity.surface, force, position, 5, 13, 500, 160, entity)
    else
      damage_entities(entity.surface, force, position, 3.5, 10, 220, 80, entity)
    end
  end
  for index = 1, heavy and 6 or 3 do
    entity.surface.create_entity({
      name = "fire-flame",
      position = {x = position.x + (index % 3) - 1, y = position.y + math.floor(index / 3) - 1},
      force = forces.get()
    })
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
        audio.play(
          record.entity.surface,
          "shahed-attack-drone-flyby",
          record.entity.position,
          "flyby::" .. player.index .. "::" .. record.event_id,
          3600
        )
      end
    end
  end
end

local function retarget(record, generator)
  local force = game.forces[record.target_force_index]
  if not force or not record.entity.valid then
    return false
  end
  local target = targeting.choose(record.entity.surface, force, generator, false)
  if not target then
    return false
  end
  record.target_entity = target
  record.target_position = {x = target.position.x, y = target.position.y}
  record.orbit_center = {x = target.position.x, y = target.position.y}
  record.orbit_destination = nil
  record.approach_destination = nil
  record.mission = "approach"
  command_drone(record)
  return true
end

local function continue_after_target_loss(record, generator)
  if retarget(record, generator) then
    return
  end
  record.target_entity = nil
  if record.kind == "recon" then
    record.mission = "returning"
  else
    record.mission = "terminal"
  end
  command_drone(record)
end

local function finish_recon(surface_state, record)
  surface_state.intelligence[record.target_force_index] = math.max(
    surface_state.intelligence[record.target_force_index] or 0,
    2
  )
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
  local tracking = defense.tracking_for_position(
    surface_state,
    record.target_force_index,
    record.entity.position
  )
  if rules.drone_warning(distance_to_target,record.entity.speed,tracking > 0) then
    surface_state.alerted_events[record.event_id] = true
    local eta = rules.drone_eta(distance_to_target,record.entity.speed)
    local direction = rules.incoming_direction(record.entity.position,record.target_position)
    surface_state.warning_history[record.event_id] = {kind="air-raid",tick=game.tick,
      eta=eta,direction=direction,position=record.entity.position,target=record.target_position}
    radar_signals.record_detection(record.entity.surface,record.target_force_index,record.entity.position,"air",game.tick)
    local force = game.forces[record.target_force_index]
    if force then
      alerts.air_raid(
        force,
        record.target_entity and record.target_entity.valid and record.target_entity or record.entity,
        record.event_size,
        {"shahed-attack-direction."..direction},
        record.event_id,
        math.ceil(eta)
      )
    end
  end
end

local function update_record(surface_state, record, tick, generator)
  if not record.entity or not record.entity.valid then
    return false
  end
  if tick - record.spawn_tick > 20 * 60 * 60 then
    record.entity.destroy()
    return false
  end

  local current_position = {x = record.entity.position.x, y = record.entity.position.y}
  record.last_motion = flight_math.normalized_motion(
    record.last_position or current_position,
    current_position,
    record.entity.orientation
  )
  record.last_position = current_position

  -- Unit path commands can be dropped after nearby explosions or transient
  -- pathfinder failures. Reassert the independent flight plan periodically.
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

  if record.mission ~= "terminal"
    and (not record.target_entity or not record.target_entity.valid) then
    continue_after_target_loss(record, generator)
  end

  if record.mission == "approach" and record.approach_destination
    and defense_math.distance(record.entity.position, record.approach_destination) <= 3 then
    record.approach_destination = nil
    command_drone(record)
  end

  local distance_to_target = defense_math.distance(record.entity.position, record.target_position)
  maybe_alert(surface_state, record, distance_to_target)

  if record.kind == "recon" then
    if record.mission == "approach" and distance_to_target <= 18 then
      record.mission = "scanning"
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
  for surface_index, surface_state in pairs(storage.shahed_attack.surfaces) do
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

function raids.on_script_trigger_effect(event)
  local wreck_outcome = event.effect_id
    and event.effect_id:match("^shahed%-attack%-wreck%-completed%-(%a+)$")
  if wreck_outcome == "safe" or wreck_outcome == "fuel" or wreck_outcome == "warhead" then
    local event_surface = event.surface_index and game.get_surface(event.surface_index) or nil
    if not event_surface and event.source_entity and event.source_entity.valid then
      event_surface = event.source_entity.surface
    end
    if event_surface then
      local surface_state = state.ensure_surface(event_surface)
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
  if event.effect_id == "shahed-attack-strike-impact" then
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

return raids
