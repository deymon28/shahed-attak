local alerts = require("scripts.alerts")
local ballistics = require("scripts.ballistics")
local infrastructure = require("scripts.infrastructure")
local random = require("scripts.lib.random")
local radar_signals = require("scripts.radar_signals")
local raids = require("scripts.raids")
local state = require("scripts.state")
local targeting = require("scripts.targeting")
local visual_effects = require("scripts.visual_effects")

local commands_api = {}

local function reply(player, message)
  if player then
    player.print(message)
  else
    log(message)
  end
end

local function context(event)
  local player = event.player_index and game.get_player(event.player_index) or nil
  if player and not player.admin then
    player.print({"shahed-attack-message.admin-only"})
    return nil
  end
  local surface = player and player.surface or game.surfaces[1]
  local force = player and player.force or game.forces.player
  return player, surface, force
end

local function find_target(surface, force, generator, player)
  if player and targeting.is_target(player.selected) and player.selected.force == force then
    targeting.register(player.selected)
    return player.selected
  end
  local target = targeting.choose(surface, force, generator, true)
  if target then
    return target
  end
  if player then
    return targeting.choose_near_position(surface, force, player.position, 256)
  end
  return nil
end

local function status_text(surface_state)
  local drones = 0
  local missiles = 0
  for _ in pairs(surface_state.active_drones) do drones = drones + 1 end
  for _ in pairs(surface_state.active_missiles) do missiles = missiles + 1 end
  return string.format(
    "Shahed Attack: drones=%d missiles=%d raids=%d recon=%d ballistic=%d intercepted=%d next_raid_tick=%d next_ballistic_day=%d",
    drones,
    missiles,
    surface_state.counters.raids,
    surface_state.counters.recon,
    surface_state.counters.ballistic,
    surface_state.counters.intercepted,
    surface_state.next_raid_tick,
    surface_state.next_ballistic_day
  )
end

local function run(event)
  local player, surface, force = context(event)
  if not surface then
    return
  end
  local subcommand = string.lower((event.parameter or "status"):match("^%s*(%S+)") or "status")
  local surface_state = state.ensure_surface(surface)
  if subcommand == "status" then
    reply(player, status_text(surface_state))
    return
  end

  local generator = random.new(surface_state.rng_state)
  local target = find_target(surface, force, generator, player)
  if not target then
    reply(player, {"shahed-attack-message.no-target"})
    return
  end

  local event_id
  local error_message
  if subcommand == "recon" then
    event_id, error_message = raids.spawn_event(surface, force, target, "recon", 1, {force_external = true, generator = generator})
  elseif subcommand == "raid" then
    event_id, error_message = raids.spawn_event(surface, force, target, "raid", 6, {force_external = true, generator = generator})
  elseif subcommand == "heavy-raid" then
    event_id, error_message = raids.spawn_event(surface, force, target, "raid", 8, {force_external = true, generator = generator})
  elseif subcommand == "ballistic" then
    event_id, error_message = ballistics.launch(surface, force, target, nil, generator)
  else
    reply(player, {"shahed-attack-message.unknown-command", subcommand})
    return
  end
  surface_state.rng_state = generator.state
  if event_id then
    reply(player, {"shahed-attack-message.event-created", event_id})
  else
    reply(player, {"shahed-attack-message.event-failed", error_message or "unknown"})
  end
end

local function remote_schedule(request)
  if type(request) ~= "table" then
    return {ok = false, error = "request-must-be-table"}
  end
  local surface = game.get_surface(request.surface_index or 1)
  local force = game.forces[request.target_force_name or "player"]
  if not surface or not force then
    return {ok = false, error = "invalid-surface-or-force"}
  end
  local surface_state = state.ensure_surface(surface)
  local generator = random.new(surface_state.rng_state)
  local target
  if request.target_position then
    target = targeting.choose_near_position(surface, force, request.target_position, 8)
  else
    target = targeting.choose(surface, force, generator, true)
  end
  if not target then
    return {ok = false, error = "no-target"}
  end

  local event_id
  local error_message
  if request.kind == "ballistic" then
    local source
    if request.source_position then
      source = surface.find_entities_filtered({
        name = "shahed-attack-ballistic-site",
        position = request.source_position,
        radius = 8
      })[1]
    end
    event_id, error_message = ballistics.launch(surface, force, target, source, generator)
  elseif request.kind == "recon" or request.kind == "raid" or request.kind == "mixed" then
    local size = math.max(1, math.min(12, math.floor(tonumber(request.size) or 1)))
    event_id, error_message = raids.spawn_event(
      surface,
      force,
      target,
      request.kind,
      size,
      {
        force_external = true,
        generator = generator,
        origin_position = request.origin_position
      }
    )
  else
    return {ok = false, error = "invalid-kind"}
  end
  surface_state.rng_state = generator.state
  return event_id and {ok = true, event_id = event_id} or {ok = false, error = error_message or "spawn-failed"}
end

local function remote_state(surface_index)
  local surface_state = state.get_surface(surface_index)
  if not surface_state then
    return nil
  end
  local drones = 0
  local drone_details = {}
  local missiles = 0
  local ballistic_sound_sources = 0
  local missile_details = {}
  for unit_number, drone in pairs(surface_state.active_drones) do
    drones = drones + 1
    drone_details[#drone_details + 1] = {
      unit_number = unit_number,
      event_id = drone.event_id,
      origin = drone.origin,
      source_unit_number = drone.source_unit_number or (drone.source and drone.source.valid and drone.source.unit_number or nil),
      kind = drone.kind,
      mission = drone.mission,
      position = drone.entity and drone.entity.valid and {
        x = drone.entity.position.x,
        y = drone.entity.position.y
      } or nil,
      target_position = drone.target_position and {
        x = drone.target_position.x,
        y = drone.target_position.y
      } or nil,
      target_valid = drone.target_entity and drone.target_entity.valid or false
    }
  end
  for missile_id, missile in pairs(surface_state.active_missiles) do
    missiles = missiles + 1
    local has_sound_source = missile.sound_source and missile.sound_source.valid or false
    if has_sound_source then
      ballistic_sound_sources = ballistic_sound_sources + 1
    end
    missile_details[#missile_details + 1] = {
      id = missile_id,
      position = {x = missile.position.x, y = missile.position.y},
      duration_ticks = missile.duration,
      eta_seconds = missile.eta_seconds,
      phase = missile.phase,
      origin = missile.origin,
      source_unit_number = missile.source_unit_number,
      warning_seconds = missile.warning_seconds,
      tier = missile.tier,
      trail_emissions = missile.trail_emissions or 0,
      has_sound_source = has_sound_source,
      previous_position = missile.previous_position and {
        x = missile.previous_position.x,
        y = missile.previous_position.y
      } or nil,
      progress = missile.progress or 0,
      step_distance = missile.step_distance or 0,
      distance_to_target = missile.distance_to_target,
      impact_count = missile.impact_count or 0,
      cleanup_count = missile.cleanup_count or 0
    }
  end
  local counters = {}
  for name, value in pairs(surface_state.counters) do
    counters[name] = value
  end
  local audio_counters = {}
  for name, value in pairs(storage.shahed_attack.audio_counters or {}) do
    audio_counters[name] = value
  end
  local delivery = alerts.delivery_state(nil)
  local alert_counters = storage.shahed_attack.alert_counters or {}
  local root_state = storage.shahed_attack
  local projectiles = {}
  for id, shot in pairs(surface_state.projectiles or {}) do
    projectiles[#projectiles+1] = {id=id,kind=shot.kind,position=shot.position,
      start_tick=shot.start_tick,target_missile_id=shot.target_missile_id}
  end
  local warnings = {}
  for id, warning in pairs(surface_state.warning_history or {}) do
    warnings[#warnings+1]={id=id,kind=warning.kind,tick=warning.tick,eta=warning.eta,
      direction=warning.direction,position=warning.position,target=warning.target}
  end
  table.sort(warnings,function(a,b) return a.id<b.id end)
  local sources={}
  for kind, entities in pairs(surface_state.sources) do
    for _, entity in pairs(entities) do
      if entity and entity.valid then sources[#sources+1]={kind=kind,unit_number=entity.unit_number,position=entity.position} end
    end
  end
  return {
    projectiles=projectiles,warnings=warnings,sources=sources,
    schema_version = root_state.schema_version,
    next_raid_tick = surface_state.next_raid_tick,
    next_ballistic_day = surface_state.next_ballistic_day,
    active_drones = drones,
    drones = drone_details,
    active_missiles = missiles,
    ballistic_sound_sources = ballistic_sound_sources,
    missiles = missile_details,
    counters = counters,
    audio_counters = audio_counters,
    radar_signals = radar_signals.status(surface_index),
    visuals = visual_effects.status(surface_index),
    alert_delivery = delivery.mode,
    circuit_delivery_enabled = delivery.circuit_enabled,
    global_warning_dispatches = alert_counters.global_warning_dispatches or 0,
    helper_tables = {
      alert_sound_events = type(root_state.alert_sound_events) == "table",
      audio_cooldowns = type(root_state.audio_cooldowns) == "table",
      radar_relays = type(root_state.radar_relays) == "table",
      visual_records = type(root_state.visual_records) == "table"
    }
  }
end

local function remote_delivery_state(player_index)
  local player = player_index and game.get_player(player_index) or nil
  if player_index and not player then
    return nil
  end
  return alerts.delivery_state(player)
end

local function remote_set_alert_delivery(mode)
  local valid = {
    ["both"] = true,
    ["global-sound"] = true,
    ["circuit-only"] = true
  }
  if not valid[mode] then
    return {ok = false, error = "invalid-alert-delivery"}
  end
  settings.global["shahed-attack-alert-delivery"] = {value = mode}
  return {ok = true, mode = mode}
end

function commands_api.register()
  commands.add_command("shahed-attack", {"shahed-attack-message.command-help"}, run)
  remote.add_interface("shahed_attack", {
    set_intercept_accuracy = function(value)
      if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
        return {ok=false,error="accuracy-out-of-range"}
      end
      settings.global["shahed-attack-intercept-accuracy"]={value=value}
      return {ok=true}
    end,
    schedule_event = remote_schedule,
    get_surface_state = remote_state,
    get_alert_delivery_state = remote_delivery_state,
    set_alert_delivery = remote_set_alert_delivery
  })
end

return commands_api
