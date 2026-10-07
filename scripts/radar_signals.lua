local alert_policy = require("scripts.lib.alert_policy")
local audio = require("scripts.audio")
local state = require("scripts.state")
local visual_effects = require("scripts.visual_effects")

local radar_signals = {}

local RADAR_NAME = "shahed-attack-early-warning-radar"
local RELAY_NAME = "shahed-attack-radar-signal-relay"
local rules = require("scripts.lib.air_rules")
local DETECTION_RADIUS_SQUARED = rules.DRONE_RADAR_RANGE ^ 2
local LATCH_TICKS = 600

local function ensure_root()
  storage.shahed_attack = storage.shahed_attack or {}
  local root = storage.shahed_attack
  root.radar_relays = root.radar_relays or {}
  root.radar_relay_registrations = root.radar_relay_registrations or {}
  return root
end

local function circuit_delivery_enabled()
  local entry = settings.global["shahed-attack-alert-delivery"]
  return alert_policy.publishes_circuit(entry and entry.value or "both")
end

local function connect_color(radar, relay, connector_id)
  local radar_connector = radar.get_wire_connector(connector_id, true)
  local relay_connector = relay.get_wire_connector(connector_id, true)
  if radar_connector and relay_connector and not radar_connector.is_connected_to(relay_connector) then
    radar_connector.connect_to(relay_connector, false)
  end
end

local function connect_relay(record)
  connect_color(record.radar, record.relay, defines.wire_connector_id.circuit_red)
  connect_color(record.radar, record.relay, defines.wire_connector_id.circuit_green)
end

local function discard_record(root, unit_number, destroy_relay)
  local record = root.radar_relays[unit_number]
  if not record then
    return
  end
  if record.registration then
    root.radar_relay_registrations[record.registration] = nil
  end
  if destroy_relay and record.relay and record.relay.valid then
    record.relay.destroy()
  end
  root.radar_relays[unit_number] = nil
end

local function ensure_relay(radar)
  if not radar or not radar.valid or radar.name ~= RADAR_NAME or not radar.unit_number then
    return nil
  end
  local root = ensure_root()
  local record = root.radar_relays[radar.unit_number]
  if record and record.radar and record.radar.valid and record.relay and record.relay.valid then
    connect_relay(record)
    return record
  end
  if record then
    discard_record(root, radar.unit_number, true)
  end

  local relay = radar.surface.create_entity({
    name = RELAY_NAME,
    position = radar.position,
    force = radar.force,
    create_build_effect_smoke = false
  })
  if not relay then
    return nil
  end
  relay.destructible = false
  relay.minable = false
  relay.operable = false

  local registration = script.register_on_object_destroyed(radar)
  record = {
    radar = radar,
    relay = relay,
    registration = registration,
    air_count = 0,
    ballistic_count = 0,
    air_latch_until = 0,
    ballistic_latch_until = 0,
    alerting = false
  }
  root.radar_relays[radar.unit_number] = record
  root.radar_relay_registrations[registration] = radar.unit_number
  connect_relay(record)
  return record
end

local function squared_distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

local function live_counts(record)
  local radar = record.radar
  if radar.energy < 1000 then
    return 0, 0
  end
  local surface_state = state.get_surface(radar.surface.index)
  if not surface_state then
    return 0, 0
  end

  local air_count = 0
  for _, drone in pairs(surface_state.active_drones or {}) do
    if drone.entity
      and drone.entity.valid
      and drone.entity.surface.index == radar.surface.index
      and drone.target_force_index == radar.force.index
      and drone.mission ~= "returning"
      and rules.drone_warning(math.sqrt(squared_distance(drone.entity.position,drone.target_position)),drone.entity.speed,true)
      and squared_distance(drone.entity.position, radar.position) <= DETECTION_RADIUS_SQUARED
    then
      air_count = air_count + 1
    end
  end

  local ballistic_count = 0
  for _, missile in pairs(surface_state.active_missiles or {}) do
    if missile.surface_index == radar.surface.index
      and missile.force_index == radar.force.index
      and not missile.intercepted
      and (missile.duration-(game.tick-missile.start_tick))/60 <= rules.WARNING_HORIZON
      and squared_distance(missile.position, radar.position) <= rules.BALLISTIC_RADAR_RANGE ^ 2
    then
      ballistic_count = ballistic_count + 1
    end
  end
  return air_count, ballistic_count
end

local function latched_count(live_count, previous_count, previous_until, tick)
  if live_count > 0 then
    return live_count, tick + LATCH_TICKS
  end
  if tick < previous_until then
    return previous_count, previous_until
  end
  return 0, 0
end

local function set_outputs(relay, air_count, ballistic_count, enabled)
  local behavior = relay.get_or_create_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section("shahed-attack")
  section.set_slot(1, {
    value = {type = "virtual", name = "shahed-attack-air-raid-signal", quality = "normal"},
    min = air_count
  })
  section.set_slot(2, {
    value = {type = "virtual", name = "shahed-attack-ballistic-signal", quality = "normal"},
    min = ballistic_count
  })
  section.active = enabled and (air_count > 0 or ballistic_count > 0)
  behavior.enabled = enabled
end

local function update_record(record, tick)
  local live_air, live_ballistic = live_counts(record)
  local live_alerting = live_air > 0 or live_ballistic > 0
  if live_alerting and not record.live_alerting then
    audio.play(
      record.radar.surface,
      "shahed-attack-radar-ping",
      record.radar.position,
      "radar-ping::" .. record.radar.unit_number,
      300
    )
  end
  record.live_alerting = live_alerting
  record.air_count, record.air_latch_until = latched_count(
    live_air,
    record.air_count,
    record.air_latch_until,
    tick
  )
  record.ballistic_count, record.ballistic_latch_until = latched_count(
    live_ballistic,
    record.ballistic_count,
    record.ballistic_latch_until,
    tick
  )
  record.alerting = record.air_count > 0 or record.ballistic_count > 0
  visual_effects.set_radar_alert(record.radar, record.alerting)
  if circuit_delivery_enabled() then
    set_outputs(record.relay, record.air_count, record.ballistic_count, true)
  else
    set_outputs(record.relay, 0, 0, false)
  end
end

function radar_signals.record_detection(surface,force_index,position,kind,tick)
  local range = kind == "ballistic" and rules.BALLISTIC_RADAR_RANGE or rules.DRONE_RADAR_RANGE
  for _, record in pairs(ensure_root().radar_relays) do
    local radar=record.radar
    if radar and radar.valid and record.relay and record.relay.valid
      and radar.surface.index == surface.index and radar.force.index == force_index
      and radar.energy >= 1000 and squared_distance(position,radar.position) <= range*range then
      if kind == "ballistic" then
        record.ballistic_count=math.max(1,record.ballistic_count)
        record.ballistic_latch_until=tick+LATCH_TICKS
      else
        record.air_count=math.max(1,record.air_count)
        record.air_latch_until=tick+LATCH_TICKS
      end
      update_record(record,tick)
    end
  end
end

function radar_signals.initialize()
  local root = ensure_root()
  for unit_number, record in pairs(root.radar_relays) do
    if not record.radar or not record.radar.valid then
      discard_record(root, unit_number, true)
    elseif not record.relay or not record.relay.valid then
      discard_record(root, unit_number, false)
    end
  end

  for _, surface in pairs(game.surfaces) do
    for _, radar in ipairs(surface.find_entities_filtered({name = RADAR_NAME})) do
      ensure_relay(radar)
    end
  end

  local known_relays = {}
  for _, record in pairs(root.radar_relays) do
    if record.relay and record.relay.valid and record.relay.unit_number then
      known_relays[record.relay.unit_number] = true
    end
  end
  for _, surface in pairs(game.surfaces) do
    for _, relay in ipairs(surface.find_entities_filtered({name = RELAY_NAME})) do
      if not known_relays[relay.unit_number] then
        relay.destroy()
      end
    end
  end
end

function radar_signals.on_entity_created(entity)
  if entity and entity.valid and entity.name == RADAR_NAME then
    ensure_relay(entity)
  end
end

function radar_signals.on_object_destroyed(event)
  local root = ensure_root()
  local unit_number = root.radar_relay_registrations[event.registration_number]
  if unit_number then
    discard_record(root, unit_number, true)
  end
end

function radar_signals.update(tick)
  local root = ensure_root()
  for unit_number, record in pairs(root.radar_relays) do
    if not record.radar or not record.radar.valid or not record.relay or not record.relay.valid then
      discard_record(root, unit_number, true)
    else
      connect_relay(record)
      update_record(record, tick)
    end
  end
end

function radar_signals.status(surface_index)
  local root = ensure_root()
  local result = {}
  for unit_number, record in pairs(root.radar_relays) do
    if record.radar and record.radar.valid and record.radar.surface.index == surface_index then
      result[#result + 1] = {
        radar_unit_number = unit_number,
        air_count = record.air_count,
        ballistic_count = record.ballistic_count,
        air_latch_until = record.air_latch_until,
        ballistic_latch_until = record.ballistic_latch_until,
        alerting = record.alerting
      }
    end
  end
  table.sort(result, function(a, b)
    return a.radar_unit_number < b.radar_unit_number
  end)
  return result
end

return radar_signals
