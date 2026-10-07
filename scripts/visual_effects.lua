local flight_math = require("scripts.lib.flight_math")
local abm_launch = require("scripts.lib.abm_launch")
local state = require("scripts.state")

local visual_effects = {}

local OWNER_ANIMATIONS = {
  ["shahed-attack-airfield"] = "shahed-attack-airfield-overlay",
  ["shahed-attack-ballistic-site"] = "shahed-attack-ballistic-site-overlay"
}

local function root()
  return state.root()
end

local function destroy_render(render)
  if render and render.valid then
    render.destroy()
  end
end

local function discard(unit_number)
  local data = root()
  local record = data.visual_records[unit_number]
  if not record then
    return
  end
  destroy_render(record.idle)
  destroy_render(record.alert)
  destroy_render(record.launch)
  data.visual_active_launches[unit_number] = nil
  if record.registration then
    data.visual_registrations[record.registration] = nil
  end
  data.visual_records[unit_number] = nil
end

local function ensure_record(entity)
  if not entity or not entity.valid or not entity.unit_number then
    return nil
  end
  local data = root()
  local record = data.visual_records[entity.unit_number]
  if record and record.owner and record.owner.valid then
    return record
  end
  if record then
    discard(entity.unit_number)
  end
  record = {
    owner = entity,
    registration = script.register_on_object_destroyed(entity)
  }
  data.visual_records[entity.unit_number] = record
  data.visual_registrations[record.registration] = entity.unit_number
  return record
end

local function ensure_idle(entity)
  local animation_name = OWNER_ANIMATIONS[entity.name]
  if not animation_name then
    return
  end
  local record = ensure_record(entity)
  if record.idle_suspended_until and record.idle_suspended_until > game.tick then
    return
  end
  if record.idle and record.idle.valid then
    return
  end
  record.idle = rendering.draw_animation({
    animation = animation_name,
    target = entity,
    surface = entity.surface,
    render_layer = "higher-object-above",
    animation_speed = 0.12
  })
end

function visual_effects.initialize()
  local data = root()
  for unit_number, record in pairs(data.visual_records) do
    if not record.owner or not record.owner.valid then
      discard(unit_number)
    end
  end
  for _, surface in pairs(game.surfaces) do
    for entity_name in pairs(state.supported(surface) and OWNER_ANIMATIONS or {}) do
      for _, entity in ipairs(surface.find_entities_filtered({name = entity_name})) do
        ensure_idle(entity)
      end
    end
  end
end

function visual_effects.on_entity_created(entity)
  if entity and entity.valid and OWNER_ANIMATIONS[entity.name] then
    ensure_idle(entity)
  end
end

function visual_effects.on_object_destroyed(event)
  local data = root()
  local unit_number = data.visual_registrations[event.registration_number]
  if unit_number then
    discard(unit_number)
  end
end

function visual_effects.set_radar_alert(radar, enabled)
  if not radar or not radar.valid or radar.name ~= "shahed-attack-early-warning-radar" then
    return
  end
  local record = ensure_record(radar)
  if enabled then
    if not record.alert or not record.alert.valid then
      record.alert = rendering.draw_animation({
        animation = "shahed-attack-radar-alert",
        target = radar,
        surface = radar.surface,
        render_layer = "higher-object-above",
        animation_speed = 0.2
      })
    end
  else
    destroy_render(record.alert)
    record.alert = nil
  end
end

function visual_effects.play_ballistic_launch(source)
  if not source or not source.valid or source.name ~= "shahed-attack-ballistic-site" then
    return nil
  end
  local counters = root().visual_counters
  counters.ballistic_launches = counters.ballistic_launches + 1
  local record = ensure_record(source)
  destroy_render(record.idle)
  destroy_render(record.launch)
  record.idle = nil
  record.idle_suspended_until = game.tick + 80
  root().visual_active_launches[source.unit_number] = true
  record.launch = rendering.draw_animation({
    animation = "shahed-attack-ballistic-site-launch",
    target = source,
    surface = source.surface,
    render_layer = "higher-object-above",
    animation_speed = 0.25,
    time_to_live = 80
  })
  return record.launch
end

function visual_effects.update(tick)
  local data = root()
  for unit_number in pairs(data.visual_active_launches) do
    local record = data.visual_records[unit_number]
    if not record or not record.owner or not record.owner.valid then
      discard(unit_number)
      data.visual_active_launches[unit_number] = nil
    elseif tick >= record.idle_suspended_until then
      destroy_render(record.launch)
      record.launch = nil
      record.idle_suspended_until = nil
      data.visual_active_launches[unit_number] = nil
      ensure_idle(record.owner)
    end
  end
end

function visual_effects.play_abm_launch(battery, target_position)
  if not battery or not battery.valid or battery.name ~= "shahed-attack-abm-battery" then
    return nil
  end
  battery.orientation = flight_math.orientation(battery.position, target_position)
  local counters = root().visual_counters
  counters.abm_launches = counters.abm_launches + 1
  return rendering.draw_animation({
    animation = "shahed-attack-abm-launch-" .. abm_launch.direction_index(battery.orientation),
    target = {x=battery.position.x, y=battery.position.y},
    surface = battery.surface,
    render_layer = "higher-object-above",
    -- The owning projectile advances the frame together with its launch pose.
    animation_speed = 0,
    animation_offset = 0,
    time_to_live = abm_launch.duration_ticks
  })
end

function visual_effects.status(surface_index)
  local counters = root().visual_counters
  local result = {
    owners = 0,
    idle = 0,
    alerts = 0,
    ballistic_launches = counters.ballistic_launches,
    abm_launches = counters.abm_launches
  }
  for _, record in pairs(root().visual_records) do
    if record.owner and record.owner.valid and record.owner.surface.index == surface_index then
      result.owners = result.owners + 1
      if record.idle and record.idle.valid then result.idle = result.idle + 1 end
      if record.alert and record.alert.valid then result.alerts = result.alerts + 1 end
    end
  end
  return result
end

return visual_effects
