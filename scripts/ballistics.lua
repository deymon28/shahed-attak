local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local balance = require("scripts.balance")
local defense = require("scripts.defense")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local infrastructure = require("scripts.infrastructure")
local forces = require("scripts.forces")
local random = require("scripts.lib.random")
local state = require("scripts.state")
local visual_effects = require("scripts.visual_effects")

local rules = require("scripts.lib.air_rules")
local radar_signals = require("scripts.radar_signals")

local ballistics = {}

local function setting(name, fallback)
  local value = settings.global[name]
  return value and value.value or fallback
end

local function create_marker(missile, radius)
  if missile.marker and missile.marker.valid then
    missile.marker.radius = radius
    return
  end
  missile.marker = rendering.draw_circle({
    color = {r = 1, g = 0.15, b = 0.05, a = 0.9},
    radius = radius,
    width = 4,
    target = missile.target_position,
    surface = missile.surface_index,
    forces = {game.forces[missile.force_index]},
    blink_interval = 30
  })
end

local function cleanup(missile)
  if missile.sound_source and missile.sound_source.valid then
    missile.sound_source.destroy()
  end
  if missile.render and missile.render.valid then
    missile.render.destroy()
  end
  if missile.marker and missile.marker.valid then
    missile.marker.destroy()
  end
  if missile.light and missile.light.valid then missile.light.destroy() end
  if missile.shadow and missile.shadow.valid then missile.shadow.destroy() end
end

function ballistics.launch(surface, target_force, target_entity, source, generator)
  if not surface or not target_force or not target_entity or not target_entity.valid then
    return nil, "missing-target"
  end
  local surface_state = state.ensure_surface(surface)
  local target_position = {x = target_entity.position.x, y = target_entity.position.y}
  local tier = game.forces.enemy.get_evolution_factor(surface) >= 0.75 and 1 or 0
  local origin = source and source.valid
    and {x = source.position.x, y = source.position.y}
    or infrastructure.external_origin(target_position, generator, 1000, 1400)
  local duration_ticks = rules.ballistic_duration(defense_math.distance(origin, target_position))
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
    source_unit_number = source and source.valid and source.unit_number or nil,
    tier = tier,
    detected = false,
    terminal_alerted = false,
    intercepted = false,
    attempted_batteries = {},
    probabilities = {},
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
  missile.render = rendering.draw_sprite({
    sprite = "shahed-attack-ballistic-missile-sprite",
    target = origin,
    surface = surface,
    orientation = flight_math.orientation(origin, target_position),
    render_layer = "air-object",
    visible = not (source and source.valid)
  })
  missile.shadow = rendering.draw_sprite({sprite="shahed-attack-ballistic-missile-sprite",
    target=origin,surface=surface,orientation=flight_math.orientation(origin,target_position),
    tint={r=0,g=0,b=0,a=0.28},x_scale=0.65,y_scale=0.65,render_layer="object-under",
    visible=not (source and source.valid)})
  missile.light = rendering.draw_light({
    sprite = "utility/light_medium",
    target = origin,
    surface = surface,
    color = {r = 1, g = 0.35, b = 0.08},
    intensity = 0.7,
    scale = 1.4,
    minimum_darkness = 0
  })
  surface_state.active_missiles[event_id] = missile
  audio.play(
    surface,
    "shahed-attack-ballistic-launch",
    origin,
    "ballistic-launch::" .. event_id,
    1
  )
  if source and source.valid then
    visual_effects.play_ballistic_launch(source)
    -- The launch overlay owns the rising body for its first fifteen frames.
    missile.visual_handoff_tick = game.tick + 60
  end
  surface_state.counters.events = surface_state.counters.events + 1
  surface_state.counters.ballistic = surface_state.counters.ballistic + 1
  return event_id
end

local function impact(missile, surface_state, generator)
  local surface = game.get_surface(missile.surface_index)
  local force = game.forces[missile.force_index]
  if not surface or not force then
    return
  end
  audio.play(
    surface,
    "shahed-attack-ballistic-impact",
    missile.target_position,
    "ballistic-impact::" .. missile.id,
    1
  )
  local multiplier = setting("shahed-attack-damage-multiplier", 1)
  local victims = surface.find_entities_filtered({
    position = missile.target_position,
    radius = 32,
    force = force
  })
  for _, victim in ipairs(victims) do
    if victim.valid and victim.health then
      local distance = defense_math.distance(missile.target_position, victim.position)
      if distance <= 5 then
        victim.damage(1800 * multiplier, forces.get(), "explosion")
        if victim.valid then
          victim.damage(400 * multiplier, forces.get(), "physical")
        end
      elseif distance <= 14 then
        victim.damage(700 * multiplier, forces.get(), "explosion")
      elseif distance <= 24 then
        victim.damage(300 * multiplier, forces.get(), "explosion")
      else
        victim.damage(140 * multiplier, forces.get(), "explosion")
      end
    end
  end
  surface.create_entity({name = "massive-explosion", position = missile.target_position})
  surface.create_entity({name = "big-artillery-explosion", position = missile.target_position})
  surface.create_entity({name = "huge-scorchmark", position = missile.target_position})
  for index = 1, 18 do
    local angle = generator:range_float(0, math.pi * 2)
    local distance = generator:range_float(3, 22)
    surface.create_entity({
      name = index <= 8 and "big-explosion" or "medium-explosion",
      position = {
        x = missile.target_position.x + math.cos(angle) * distance,
        y = missile.target_position.y + math.sin(angle) * distance
      }
    })
  end
  for _ = 1, 20 do
    local angle = generator:range_float(0, math.pi * 2)
    local distance = generator:range_float(4, 28)
    surface.create_entity({
      name = "fire-flame",
      position = {
        x = missile.target_position.x + math.cos(angle) * distance,
        y = missile.target_position.y + math.sin(angle) * distance
      },
      force = forces.get()
    })
  end
end

local function finish_missile(missile, surface_state, reason, generator)
  if missile.finished then
    return false
  end
  missile.finished = true
  if reason == "impact" then
    impact(missile, surface_state, generator)
    missile.impact_count = missile.impact_count + 1
    surface_state.counters.ballistic_impacts = surface_state.counters.ballistic_impacts + 1
  end
  cleanup(missile)
  missile.cleanup_count = missile.cleanup_count + 1
  surface_state.counters.ballistic_cleanups = surface_state.counters.ballistic_cleanups + 1
  return false
end

local function update_missile(missile, surface_state, tick, generator)
  local surface = game.get_surface(missile.surface_index)
  local force = game.forces[missile.force_index]
  if not surface or not force then
    return finish_missile(missile, surface_state, "invalid", generator)
  end
  if missile.intercepted then
    return finish_missile(missile,surface_state,"intercepted",generator)
  end
  local previous_position = {x = missile.position.x, y = missile.position.y}
  missile.previous_position = previous_position
  local elapsed = tick - missile.start_tick
  local time_progress = math.min(1, elapsed / missile.duration)
  missile.progress = missile.flight_profile == 2 and rules.ballistic_progress(elapsed,missile.duration) or time_progress
  missile.position = defense_math.lerp(missile.origin,missile.target_position,missile.progress)
  missile.eta_seconds = math.max(0,(missile.duration-elapsed)/60)
  missile.phase = time_progress < 0.12 and "boost" or (missile.eta_seconds <= 8 and "terminal" or "cruise")
  missile.visual_position = {x=missile.position.x,y=missile.position.y-math.sin(time_progress*math.pi)*5}
  local progress = missile.progress
  missile.step_distance = defense_math.distance(previous_position, missile.position)
  missile.distance_to_target = defense_math.distance(missile.position, missile.target_position)
  if missile.sound_source and missile.sound_source.valid then
    missile.sound_source.teleport(missile.position)
  end
  if missile.render and missile.render.valid then
    missile.render.visible = not missile.visual_handoff_tick or tick >= missile.visual_handoff_tick
    missile.render.target = missile.visual_position
    local scale = 0.75 + math.sin(progress * math.pi) * 0.15
    missile.render.x_scale = scale
    missile.render.y_scale = scale
  end
  if missile.light and missile.light.valid then
    missile.light.target = missile.visual_position
    missile.light.scale = progress >= 0.75 and 2.2 or 1.4
  end
  if missile.shadow and missile.shadow.valid then
    missile.shadow.target=missile.position
    missile.shadow.visible = not missile.visual_handoff_tick or tick >= missile.visual_handoff_tick
  end
  if tick % 8 == 0 then
    surface.create_trivial_smoke({name = "smoke-fast", position = missile.visual_position})
    missile.trail_emissions = missile.trail_emissions + 1
  end

  local tracking = defense.tracking_for_position(surface_state,missile.force_index,missile.position,"ballistic")
  local eligible_warning = tracking > 0 and missile.eta_seconds <= rules.WARNING_HORIZON
  local fallback_warning = missile.eta_seconds <= 8
  if not missile.detected and (eligible_warning or fallback_warning) then
    missile.detected = true
    missile.terminal_alerted = not eligible_warning
    missile.detected_tick = tick
    local direction = rules.incoming_direction(missile.position,missile.target_position)
    missile.warning_seconds = missile.eta_seconds
    surface_state.warning_history[missile.id] = {kind="ballistic",tick=tick,
      eta=missile.eta_seconds,direction=direction,position=missile.position,target=missile.target_position}
    alerts.ballistic(force,missile.target_entity,math.ceil(missile.eta_seconds),
      missile.target_position,missile.id,{"shahed-attack-direction."..direction})
    radar_signals.record_detection(surface,missile.force_index,missile.position,"ballistic",tick)
  end
  if missile.detected then create_marker(missile,math.max(8,24-16*tracking)) end
  -- Batteries have their own short-range tracker; the large radar supplies early warning.
  defense.try_intercepts(missile,surface_state)

  if progress >= 1 then
    return finish_missile(missile, surface_state, "impact", generator)
  end
  return true
end

function ballistics.update(tick)
  for _, surface_state in pairs(storage.shahed_attack.surfaces) do
    local generator = random.new(surface_state.rng_state)
    for missile_id, missile in pairs(surface_state.active_missiles) do
      if not update_missile(missile, surface_state, tick, generator) then
        surface_state.active_missiles[missile_id] = nil
      end
    end
    surface_state.rng_state = generator.state
  end
end

return ballistics
