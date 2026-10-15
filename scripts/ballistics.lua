-- Ballistic missiles: launched from a real launch site, flying a boost/
-- cruise/terminal profile toward a point fixed at launch.
local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local config = require("scripts.lib.config")
local defense = require("scripts.defense")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local forces = require("scripts.forces")
local radar_signals = require("scripts.radar_signals")
local random = require("scripts.lib.random")
local rules = require("scripts.lib.air_rules")
local state = require("scripts.state")
local visual_effects = require("scripts.visual_effects")

local ballistics = {}

local MARKER_COLOR = {r = 1, g = 0.15, b = 0.05, a = 0.9}
-- How far beyond launcher range a missile may travel between candidate
-- refreshes (twice a second); terminal speed stays well below this.
local LAUNCHER_MARGIN = 64
local REFRESH_TICKS = 30

local function create_marker(missile, radius)
  if missile.marker and missile.marker.valid then
    if missile.marker_radius == radius then return end
    missile.marker_radius = radius
    missile.marker.radius = radius
    if missile.chart_marker and missile.chart_marker.valid then missile.chart_marker.radius = radius end
    return
  end
  local force = game.forces[missile.force_index]
  missile.marker = rendering.draw_circle({
    color = MARKER_COLOR, radius = radius, width = 4, target = missile.target_position,
    surface = missile.surface_index, forces = {force}, blink_interval = 30
  })
  -- The same impact area on the map view.
  missile.chart_marker = rendering.draw_circle({
    color = MARKER_COLOR, radius = radius, width = 3, target = missile.target_position,
    surface = missile.surface_index, forces = {force}, blink_interval = 30, render_mode = "chart"
  })
end

local function cleanup(missile)
  for _, field in ipairs({"render", "marker", "chart_marker", "light", "shadow"}) do
    local render = missile[field]
    if render and render.valid then render.destroy() end
  end
  if missile.sound_source and missile.sound_source.valid then
    missile.sound_source.destroy()
  end
end

-- options.class selects the missile class; options.aim_point overrides the
-- target position (salvos aim at distinct points around one area).
function ballistics.launch(surface, target_force, target_entity, source, generator, options)
  options = options or {}
  if not surface or not target_force or not target_entity or not target_entity.valid then
    return nil, "missing-target"
  end
  if not source or not source.valid then
    return nil, "no-source"
  end
  local surface_state = state.ensure_surface(surface)
  if not surface_state then
    return nil, "unsupported-surface"
  end
  generator = generator or random.new(surface_state.rng_state)
  local class = options.class or "medium"
  local stats = rules.class_stats(class)
  local aim = options.aim_point or target_entity.position
  local offset = rules.aim_error(stats.cep, generator:next_float(), generator:next_float())
  local target_position = {x = aim.x + offset.x, y = aim.y + offset.y}
  local origin = {x = source.position.x, y = source.position.y}
  local duration_ticks = rules.ballistic_duration(defense_math.distance(origin, target_position), class)
  local event_id = state.next_event_id()
  local missile = {
    id = event_id,
    surface_index = surface.index,
    force_index = target_force.index,
    target_entity = target_entity,
    target_position = target_position,
    origin = origin,
    position = {x = origin.x, y = origin.y},
    start_tick = game.tick,
    duration = duration_ticks,
    flight_profile = 2,
    source_unit_number = source.unit_number,
    class = class,
    salvo_id = options.salvo_id,
    detected = false,
    terminal_alerted = false,
    intercepted = false,
    trail_emissions = 0,
    progress = 0,
    step_distance = 0,
    distance_to_target = defense_math.distance(origin, target_position),
    impact_count = 0,
    cleanup_count = 0
  }
  missile.sound_source = surface.create_entity({
    name = "shahed-attack-ballistic-sound-source",
    position = origin,
    force = forces.get(),
    create_build_effect_smoke = false
  })
  if missile.sound_source then
    missile.sound_source.destructible = false
    missile.sound_source.minable = false
    missile.sound_source.operable = false
  end
  local orientation = flight_math.orientation(origin, target_position)
  missile.render = rendering.draw_sprite({
    sprite = "shahed-attack-ballistic-missile-sprite", target = origin, surface = surface,
    orientation = orientation, render_layer = "air-object", visible = false,
    x_scale = stats.scale, y_scale = stats.scale
  })
  missile.shadow = rendering.draw_sprite({
    sprite = "shahed-attack-ballistic-missile-sprite", target = origin, surface = surface,
    orientation = orientation, tint = {r = 0, g = 0, b = 0, a = 0.28},
    x_scale = stats.scale * 0.8, y_scale = stats.scale * 0.8, render_layer = "object-under", visible = false
  })
  missile.light = rendering.draw_light({
    sprite = "utility/light_medium", target = origin, surface = surface,
    color = {r = 1, g = 0.35, b = 0.08}, intensity = 0.7, scale = 1.4, minimum_darkness = 0
  })
  surface_state.active_missiles[event_id] = missile
  audio.play(surface, "shahed-attack-ballistic-launch", origin, "ballistic-launch::" .. event_id, 1)
  visual_effects.play_ballistic_launch(source)
  -- The launch overlay owns the rising body for its first frames.
  missile.visual_handoff_tick = game.tick + 60
  surface_state.counters.events = surface_state.counters.events + 1
  surface_state.counters.ballistic = surface_state.counters.ballistic + 1
  return event_id
end

local function impact(missile, generator)
  local surface = game.get_surface(missile.surface_index)
  local force = game.forces[missile.force_index]
  if not surface or not force then
    return
  end
  local center = missile.target_position
  audio.play(surface, "shahed-attack-ballistic-impact", center, "ballistic-impact::" .. missile.id, 1)
  local multiplier = config.global("shahed-attack-ballistic-damage-multiplier")
  local rings = rules.warhead_rings(missile.class)
  local attacker = forces.get()
  local victims = surface.find_entities_filtered({position = center, radius = rings[#rings].radius, force = force})
  for _, victim in ipairs(victims) do
    if victim.valid and victim.health then
      local distance = defense_math.distance(center, victim.position)
      for _, ring in ipairs(rings) do
        if distance <= ring.radius then
          victim.damage(ring.explosion * multiplier, attacker, "explosion")
          if ring.physical and victim.valid then
            victim.damage(ring.physical * multiplier, attacker, "physical")
          end
          break
        end
      end
    end
  end
  local stats = rules.class_stats(missile.class)
  local spread = 22 * stats.radius
  surface.create_entity({name = "massive-explosion", position = center})
  surface.create_entity({name = "big-artillery-explosion", position = center})
  surface.create_entity({name = stats.radius >= 0.85 and "huge-scorchmark" or "big-scorchmark", position = center})
  local explosions = math.floor(18 * stats.radius + 0.5)
  for index = 1, explosions do
    local angle = generator:range_float(0, math.pi * 2)
    local distance = generator:range_float(3, spread)
    surface.create_entity({
      name = index <= explosions / 2 and "big-explosion" or "medium-explosion",
      position = {x = center.x + math.cos(angle) * distance, y = center.y + math.sin(angle) * distance}
    })
  end
  for _ = 1, math.floor(20 * stats.radius + 0.5) do
    local angle = generator:range_float(0, math.pi * 2)
    local distance = generator:range_float(4, spread + 6)
    surface.create_entity({
      name = "fire-flame",
      position = {x = center.x + math.cos(angle) * distance, y = center.y + math.sin(angle) * distance},
      force = attacker
    })
  end
end

local function finish_missile(missile, surface_state, reason, generator)
  if missile.finished then
    return false
  end
  missile.finished = true
  if reason == "impact" then
    impact(missile, generator)
    missile.impact_count = missile.impact_count + 1
    surface_state.counters.ballistic_impacts = surface_state.counters.ballistic_impacts + 1
  end
  cleanup(missile)
  missile.cleanup_count = missile.cleanup_count + 1
  surface_state.counters.ballistic_cleanups = surface_state.counters.ballistic_cleanups + 1
  return false
end

local function update_missile(missile, surface_state, tick, generator, surface)
  if not surface or not game.forces[missile.force_index] then
    return finish_missile(missile, surface_state, "invalid", generator)
  end
  if missile.intercepted then
    return finish_missile(missile, surface_state, "intercepted", generator)
  end
  local previous_position = {x = missile.position.x, y = missile.position.y}
  missile.previous_position = previous_position
  local elapsed = tick - missile.start_tick
  local time_progress = math.min(1, elapsed / missile.duration)
  missile.progress = missile.flight_profile == 2 and rules.ballistic_progress(elapsed, missile.duration) or time_progress
  missile.position = defense_math.lerp(missile.origin, missile.target_position, missile.progress)
  missile.eta_seconds = math.max(0, (missile.duration - elapsed) / 60)
  missile.phase = time_progress < 0.12 and "boost" or (missile.eta_seconds <= 8 and "terminal" or "cruise")
  missile.visual_position = {x = missile.position.x, y = missile.position.y - math.sin(time_progress * math.pi) * 5}
  local progress = missile.progress
  missile.step_distance = defense_math.distance(previous_position, missile.position)
  missile.distance_to_target = defense_math.distance(missile.position, missile.target_position)
  if missile.sound_source and missile.sound_source.valid then
    missile.sound_source.teleport(missile.position)
  end
  local visible = not missile.visual_handoff_tick or tick >= missile.visual_handoff_tick
  local base_scale = rules.class_stats(missile.class).scale
  local reveal = visible and not missile.shown
  if reveal then missile.shown = true end
  if missile.render and missile.render.valid then
    if reveal then missile.render.visible = true end
    missile.render.target = missile.visual_position
    local scale = base_scale + math.sin(progress * math.pi) * 0.15
    missile.render.x_scale = scale
    missile.render.y_scale = scale
  end
  if missile.light and missile.light.valid then
    missile.light.target = missile.visual_position
    if progress >= 0.75 and not missile.terminal_light then
      missile.terminal_light = true
      missile.light.scale = 2.2
    end
  end
  if missile.shadow and missile.shadow.valid then
    missile.shadow.target = missile.position
    if reveal then missile.shadow.visible = true end
  end
  if tick % 8 == 0 then
    surface.create_trivial_smoke({name = "smoke-fast", position = missile.visual_position})
    missile.trail_emissions = missile.trail_emissions + 1
  end

  -- Radar coverage and the launchers able to engage change slowly;
  -- re-evaluate them twice a second.
  if not missile.tracking_tick or tick - missile.tracking_tick >= REFRESH_TICKS then
    missile.tracking = defense.tracking_for_position(surface_state, missile.force_index, missile.position, "ballistic")
    missile.launchers = defense.nearby_launchers(surface_state, missile.force_index, missile.position, LAUNCHER_MARGIN)
    missile.tracking_tick = tick
  end
  local tracking = missile.tracking
  local eligible_warning = tracking > 0 and missile.eta_seconds <= rules.WARNING_HORIZON
  local fallback_warning = missile.eta_seconds <= 8
  if not missile.detected and (eligible_warning or fallback_warning) then
    missile.detected = true
    missile.terminal_alerted = not eligible_warning
    missile.detected_tick = tick
    local direction = rules.incoming_direction(missile.position, missile.target_position)
    missile.warning_seconds = missile.eta_seconds
    surface_state.warning_history[missile.id] = {kind = "ballistic", tick = tick,
      eta = missile.eta_seconds, direction = direction, position = missile.position, target = missile.target_position}
    alerts.ballistic(game.forces[missile.force_index], missile.target_entity, math.ceil(missile.eta_seconds),
      missile.target_position, missile.id, {"shahed-attack-direction." .. direction})
    radar_signals.record_detection(surface, missile.force_index, missile.position, "ballistic", tick)
  end
  if missile.detected then create_marker(missile, math.max(8, 24 - 16 * tracking)) end
  -- Launchers have their own short-range trackers; the radar gives early warning.
  if #missile.launchers > 0 then
    defense.try_intercepts(missile, surface_state, missile.launchers)
  end

  if progress >= 1 then
    return finish_missile(missile, surface_state, "impact", generator)
  end
  return true
end

function ballistics.update(tick)
  for _, surface_state in pairs(storage.shahed_attack.surfaces) do
    if next(surface_state.active_missiles) then
      local generator = random.new(surface_state.rng_state)
      local surface
      for missile_id, missile in pairs(surface_state.active_missiles) do
        surface = surface or game.get_surface(missile.surface_index)
        if not update_missile(missile, surface_state, tick, generator, surface) then
          surface_state.active_missiles[missile_id] = nil
        end
      end
      surface_state.rng_state = generator.state
    end
  end
end

-- Remove every flying and queued missile without effects (admin cleanup).
function ballistics.clear(surface_state)
  local count = 0
  for missile_id, missile in pairs(surface_state.active_missiles) do
    missile.finished = true
    cleanup(missile)
    surface_state.active_missiles[missile_id] = nil
    count = count + 1
  end
  for id, pending in pairs(surface_state.pending_events) do
    if pending.kind == "ballistic" then
      surface_state.pending_events[id] = nil
      count = count + 1
    end
  end
  return count
end

return ballistics
