-- Visible flak rounds and guided interceptors.
local abm_launch = require("scripts.lib.abm_launch")
local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local defense_math = require("scripts.lib.defense_math")
local flight_math = require("scripts.lib.flight_math")
local random = require("scripts.lib.random")
local rules = require("scripts.lib.air_rules")
local visual_effects = require("scripts.visual_effects")

local ordnance = {}

-- A round that lost its target glides on briefly, then self-destructs.
local SELF_DESTRUCT_TICKS = 12

local function destroy(render)
  if render and render.valid then render.destroy() end
end

local function next_random(surface_state)
  local generator = random.new(surface_state.combat_rng_state or surface_state.rng_state)
  local value = generator:next_float()
  surface_state.combat_rng_state = generator.state
  return value
end

-- Interceptors currently flying at a target key ("m<id>" or "d<unit>").
function ordnance.engaged(surface_state, key)
  return key and surface_state.engagements and surface_state.engagements[key] or 0
end

local function release(surface_state, shot)
  local key = shot.engagement_key
  if not key then
    return
  end
  shot.engagement_key = nil
  local engagements = surface_state.engagements
  local count = (engagements[key] or 0) - 1
  engagements[key] = count > 0 and count or nil
end

local function add(surface_state, shot, surface)
  surface_state.next_projectile_id = (surface_state.next_projectile_id or 0) + 1
  shot.id = surface_state.next_projectile_id
  shot.start_tick = game.tick
  shot.position = {x = shot.origin.x, y = shot.origin.y}
  shot.render = rendering.draw_sprite({
    sprite = shot.kind == "abm" and "shahed-attack-interceptor-sprite" or "shahed-attack-flak-sprite",
    target = shot.position, surface = surface, render_layer = "air-object",
    visible = not shot.flight_tick,
    orientation = flight_math.orientation(shot.origin, shot.destination)
  })
  shot.light = rendering.draw_light({sprite = "utility/light_small", target = shot.position,
    surface = surface, color = {r = 1, g = 0.6, b = 0.2}, intensity = 0.65,
    scale = shot.kind == "abm" and 0.65 or 0.25, minimum_darkness = 0,
    visible = not shot.flight_tick})
  if shot.engagement_key then
    surface_state.engagements[shot.engagement_key] = ordnance.engaged(surface_state, shot.engagement_key) + 1
  end
  surface_state.projectiles[shot.id] = shot
  return shot
end

function ordnance.launch_interceptor(surface_state, launcher, target, accuracy, engagement_key)
  local shot = {
    kind = "abm", source = launcher, force_index = launcher.force.index,
    destination = target.visual_position or {x = target.position.x, y = target.position.y},
    target_missile_id = target.id, target_drone = target.drone, accuracy = accuracy,
    engagement_key = engagement_key
  }
  if launcher.name == "shahed-attack-abm-battery" then
    -- Fixed batteries play the baked canister launch before free flight.
    local launch_render = visual_effects.play_abm_launch(launcher, target.position)
    local direction = abm_launch.direction_index(launcher.orientation)
    local origin = {x = launcher.position.x, y = launcher.position.y}
    shot.origin = abm_launch.position(origin, direction, 0)
    shot.launch_origin = origin
    shot.launch_direction = direction
    shot.launch_render = launch_render
    shot.flight_tick = game.tick + abm_launch.handoff_ticks
  else
    shot.origin = {x = launcher.position.x, y = launcher.position.y - 0.9}
  end
  return add(surface_state, shot, launcher.surface)
end

function ordnance.launch_flak(surface_state, source, target, accuracy)
  local direction = flight_math.normalized_motion(source.position, target.position, source.orientation)
  local origin = {x = source.position.x + direction.x * 1.25, y = source.position.y + direction.y * 1.25 - 0.3}
  local duration = math.max(4, math.ceil(defense_math.distance(origin, target.position) / 2.5))
  local hit = next_random(surface_state) < accuracy
  local angle = next_random(surface_state) * math.pi * 2
  local miss_distance = hit and 0 or (2.5 + next_random(surface_state) * 3.5)
  local velocity = (target.speed or 0) * duration
  local heading = target.orientation * math.pi * 2
  return add(surface_state, {
    kind = "flak", source = source, target = target, force_index = source.force.index,
    origin = origin, duration = duration, hit = hit,
    destination = {
      x = target.position.x + math.sin(heading) * velocity + math.cos(angle) * miss_distance,
      y = target.position.y - math.cos(heading) * velocity + math.sin(angle) * miss_distance
    }
  }, source.surface)
end

local function finish_flak(surface, surface_state, shot)
  local target = shot.target
  if shot.hit and target and target.valid then
    surface_state.counters.flak_hits = (surface_state.counters.flak_hits or 0) + 1
    surface.create_entity({name = "explosion-hit", position = target.position})
    local force = game.forces[shot.force_index]
    local source = shot.source and shot.source.valid and shot.source or nil
    if force then
      target.damage(18, force, "physical", source)
      if target.valid then target.damage(12, force, "explosion", source) end
    end
  else
    surface_state.counters.flak_misses = (surface_state.counters.flak_misses or 0) + 1
    surface.create_entity({name = "explosion-hit", position = shot.destination})
  end
end

local function self_destruct(surface_state, shot, tick)
  release(surface_state, shot)
  shot.missed = true
  shot.expire_tick = math.max(tick, shot.flight_tick or tick) + SELF_DESTRUCT_TICKS
  shot.target_missile_id = nil
  shot.target_drone = nil
  shot.destination = flight_math.project_forward(shot.position,
    flight_math.normalized_motion(shot.origin, shot.position, 0), 60, 0.08)
end

local function encounter(surface, surface_state, shot, missile, tick)
  local success = next_random(surface_state) < shot.accuracy
  surface_state.counters.interceptor_encounters = (surface_state.counters.interceptor_encounters or 0) + 1
  if success then
    release(surface_state, shot)
    if shot.target_drone then
      local source = shot.source and shot.source.valid and shot.source or nil
      shot.target_drone.die(game.forces[shot.force_index], source)
      surface_state.counters.interceptor_drone_hits = (surface_state.counters.interceptor_drone_hits or 0) + 1
    else
      missile.intercepted = true
      surface_state.counters.intercepted = surface_state.counters.intercepted + 1
    end
    surface.create_entity({name = "big-explosion", position = shot.position})
    audio.play(surface, "shahed-attack-intercept-burst", shot.position, "intercept::" .. shot.id, 1)
    if missile then alerts.intercept(game.forces[shot.force_index], missile.target_entity, true, shot.accuracy) end
  else
    surface_state.counters.interceptor_misses = (surface_state.counters.interceptor_misses or 0) + 1
    -- A miss overshoots briefly and self-destructs, without a second roll.
    self_destruct(surface_state, shot, tick)
  end
  return success
end

local function update_shot(surface, surface_state, shot, tick)
  local previous = {x = shot.position.x, y = shot.position.y}
  local done = false
  if shot.kind == "flak" then
    shot.position = flight_math.lerp_clamped(shot.origin, shot.destination, tick - shot.start_tick, shot.duration)
    if tick - shot.start_tick >= shot.duration then
      finish_flak(surface, surface_state, shot)
      done = true
    end
  else
    local missile = shot.target_missile_id and surface_state.active_missiles[shot.target_missile_id]
    local drone = shot.target_drone
    local target_valid = (drone and drone.valid) or (not drone and missile and not missile.intercepted and not missile.finished)
    if not shot.missed and not target_valid then
      self_destruct(surface_state, shot, tick)
      missile = nil
    end
    if missile then shot.destination = missile.visual_position or {x = missile.position.x, y = missile.position.y} end
    if drone and drone.valid and not shot.missed then shot.destination = {x = drone.position.x, y = drone.position.y} end
    if shot.launch_render and shot.launch_render.valid then
      shot.launch_render.animation_offset = math.min(abm_launch.frame_count - 1,
        math.floor(math.max(0, tick - shot.start_tick) * abm_launch.animation_speed))
    end
    local pose = shot.flight_tick and abm_launch.geometry(shot.launch_direction)
    if shot.flight_tick and tick <= shot.flight_tick then
      -- The baked launch animation owns the body until its first empty frame.
      shot.position = abm_launch.position(shot.launch_origin, shot.launch_direction, tick - shot.start_tick)
      if shot.render and shot.render.valid then
        shot.render.target = shot.position
        shot.render.visible = tick == shot.flight_tick
        shot.render.orientation = flight_math.orientation({x = 0, y = 0}, pose.direction)
        shot.render.x_scale = pose.scale
        shot.render.y_scale = pose.scale
      end
      if shot.light and shot.light.valid then
        shot.light.target = shot.position
        shot.light.visible = tick == shot.flight_tick
      end
      return true
    end
    -- Saved projectiles without a flight_tick continue their old flight.
    local elapsed = tick - (shot.flight_tick or shot.start_tick)
    local speed = math.min(rules.INTERCEPTOR_SPEED, 0.4 + elapsed * 0.32)
    local distance = defense_math.distance(shot.position, shot.destination)
    local direction = flight_math.normalized_motion(shot.position, shot.destination, 0)
    if pose and elapsed < 6 then
      local initial = flight_math.orientation({x = 0, y = 0}, pose.direction)
      local desired = flight_math.orientation(shot.position, shot.destination)
      local difference = (desired - initial + 0.5) % 1 - 0.5
      local angle = (initial + difference * elapsed / 6) * math.pi * 2
      direction = {x = math.sin(angle), y = -math.cos(angle)}
    end
    if pose and shot.render and shot.render.valid then
      local progress = math.min(1, elapsed / 12)
      local scale = pose.scale + (1 - pose.scale) * progress * progress * (3 - 2 * progress)
      shot.render.visible = true
      shot.render.x_scale = scale
      shot.render.y_scale = scale
      if shot.light and shot.light.valid then shot.light.visible = true end
    end
    shot.position = flight_math.project_forward(shot.position, direction, math.min(speed, distance), 0)
    if shot.missed then
      if tick >= shot.expire_tick then
        surface.create_entity({name = "explosion-hit", position = shot.position})
        done = true
      end
    elseif distance <= speed and elapsed >= 6 then
      done = encounter(surface, surface_state, shot, missile, tick)
    end
    if tick % 3 == 0 then surface.create_trivial_smoke({name = "smoke-fast", position = previous}) end
    if elapsed > 180 then done = true end
  end
  if shot.render and shot.render.valid then
    shot.render.target = shot.position
    shot.render.orientation = flight_math.orientation(previous, shot.position)
  end
  if shot.light and shot.light.valid then shot.light.target = shot.position end
  return not done
end

function ordnance.update(tick)
  for surface_index, surface_state in pairs(storage.shahed_attack.surfaces) do
    if next(surface_state.projectiles) then
      local surface = game.get_surface(surface_index)
      -- Numeric IDs give a stable encounter order across save/load and multiplayer.
      local ids = {}
      for id in pairs(surface_state.projectiles) do ids[#ids + 1] = id end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local shot = surface_state.projectiles[id]
        if not surface or not update_shot(surface, surface_state, shot, tick) then
          release(surface_state, shot)
          destroy(shot.render)
          destroy(shot.light)
          destroy(shot.launch_render)
          surface_state.projectiles[id] = nil
        end
      end
    end
  end
end

-- Rebuild engagement counters from live projectiles (save upgrades).
function ordnance.recount(surface_state)
  surface_state.engagements = {}
  for _, shot in pairs(surface_state.projectiles) do
    if shot.kind == "abm" and not shot.missed then
      shot.engagement_key = shot.engagement_key or (shot.target_drone and shot.target_drone.valid
        and ("d" .. shot.target_drone.unit_number)) or (shot.target_missile_id and ("m" .. shot.target_missile_id))
      if shot.engagement_key then
        surface_state.engagements[shot.engagement_key] = ordnance.engaged(surface_state, shot.engagement_key) + 1
      end
    end
  end
end

return ordnance
