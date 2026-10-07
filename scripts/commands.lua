-- /shahed-attack console command and the shahed_attack remote interface.
-- Scripted attacks, like natural ones, always start at a real enemy base.
local alerts = require("scripts.alerts")
local ballistics = require("scripts.ballistics")
local director = require("scripts.director")
local infrastructure = require("scripts.infrastructure")
local profiler = require("scripts.profiler")
local radar_signals = require("scripts.radar_signals")
local random = require("scripts.lib.random")
local raids = require("scripts.raids")
local state = require("scripts.state")
local stats_gui = require("scripts.stats_gui")
local targeting = require("scripts.targeting")
local visual_effects = require("scripts.visual_effects")

local commands_api = {}

local SOURCE_SEARCH_RADIUS = 16

local function reply(player, message)
  if player then
    player.print(message)
  else
    log(message)
  end
end

local function nauvis_surface()
  return game.get_surface(state.SUPPORTED_SURFACE)
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
  if player and player.surface == surface then
    return targeting.choose_near_position(surface, force, player.position, 256)
  end
  return nil
end

local function count(map)
  local result = 0
  for _ in pairs(map) do result = result + 1 end
  return result
end

local function status_message(surface, surface_state)
  local schedule = director.schedule(surface, surface_state)
  return {"shahed-attack-message.status",
    count(surface_state.active_drones), count(surface_state.active_missiles),
    surface_state.counters.raids, surface_state.counters.recon, surface_state.counters.ballistic,
    surface_state.counters.intercepted, math.floor(schedule.raid_seconds), math.floor(schedule.ballistic_seconds)}
end

local function size_argument(parameter, default, maximum)
  local value = tonumber((parameter or ""):match("^%s*%S+%s+(%d+)"))
  if not value then
    return default
  end
  return math.max(1, math.min(maximum, math.floor(value)))
end

local ADMIN_COMMANDS = {recon = true, raid = true, ["heavy-raid"] = true, ["mass-raid"] = true,
  ballistic = true, clear = true}

local function run(event)
  local player = event.player_index and game.get_player(event.player_index) or nil
  local subcommand = string.lower((event.parameter or "status"):match("^%s*(%S+)") or "status")
  if subcommand == "help" then
    reply(player, {"shahed-attack-message.command-help"})
    return
  end
  if player and ADMIN_COMMANDS[subcommand] and not player.admin then
    player.print({"shahed-attack-message.admin-only"})
    return
  end
  local surface = nauvis_surface()
  local surface_state = surface and state.ensure_surface(surface)
  if not surface_state then
    reply(player, {"shahed-attack-message.unsupported-surface"})
    return
  end
  local force = player and player.force or game.forces.player

  if subcommand == "status" then
    reply(player, status_message(surface, surface_state))
    return
  elseif subcommand == "stats" then
    if player then stats_gui.open(player) end
    return
  elseif subcommand == "sources" then
    reply(player, {"shahed-attack-message.sources",
      infrastructure.count(surface_state, "airfields"), infrastructure.count(surface_state, "ballistic_sites")})
    return
  elseif subcommand == "clear" then
    local removed = raids.clear(surface_state) + ballistics.clear(surface_state)
    reply(player, {"shahed-attack-message.cleared", removed})
    return
  elseif not ADMIN_COMMANDS[subcommand] then
    reply(player, {"shahed-attack-message.unknown-command", subcommand})
    return
  end

  local generator = random.new(surface_state.rng_state)
  local target = find_target(surface, force, generator, player)
  if not target then
    reply(player, {"shahed-attack-message.no-target"})
    return
  end
  local event_id, error_message
  if subcommand == "ballistic" then
    local salvo = size_argument(event.parameter, 1, 30)
    if director.launch_salvo(surface, surface_state, force, target, generator, salvo) > 0 then
      event_id = "salvo"
    else
      error_message = "no-source"
    end
  else
    local kind, size, options = "raid", 6, {generator = generator}
    if subcommand == "recon" then
      kind, size = "recon", 1
    elseif subcommand == "heavy-raid" then
      size = size_argument(event.parameter, 8, 100)
      options.forced_kind = "heavy"
    elseif subcommand == "mass-raid" then
      size = size_argument(event.parameter, 32, 100)
    else
      size = size_argument(event.parameter, 6, 100)
    end
    event_id, error_message = raids.spawn_event(surface, force, target, kind, size, options)
  end
  surface_state.rng_state = generator.state
  if event_id then
    reply(player, {"shahed-attack-message.event-created", tostring(event_id)})
  else
    reply(player, {"shahed-attack-message.event-failed", error_message or "unknown"})
  end
end

-- Remote API -----------------------------------------------------------------

local function remote_schedule(request)
  if type(request) ~= "table" then
    return {ok = false, error = "request-must-be-table"}
  end
  local surface = game.get_surface(request.surface_index or state.SUPPORTED_SURFACE)
  local force = game.forces[request.target_force_name or "player"]
  if not surface or not force then
    return {ok = false, error = "invalid-surface-or-force"}
  end
  local surface_state = state.ensure_surface(surface)
  if not surface_state then
    return {ok = false, error = "unsupported-surface"}
  end
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
  local source_type = request.kind == "ballistic" and "ballistic_sites" or "airfields"
  -- origin_position is accepted as an alias: the source must exist there.
  local hint = request.source_position or request.origin_position
  local source
  if hint then
    source = infrastructure.source_near(surface_state, source_type, hint, SOURCE_SEARCH_RADIUS, surface)
    if not source then
      return {ok = false, error = "no-source"}
    end
  end

  local event_id, error_message
  if request.kind == "ballistic" then
    source = source or infrastructure.get_source(surface_state, "ballistic_sites", target.position, generator)
    if not source then
      return {ok = false, error = "no-source"}
    end
    event_id, error_message = ballistics.launch(surface, force, target, source, generator,
      {class = request.class or "medium"})
  elseif request.kind == "recon" or request.kind == "raid" or request.kind == "mixed" or request.kind == "heavy" then
    local size = math.max(1, math.min(100, math.floor(tonumber(request.size) or 1)))
    event_id, error_message = raids.spawn_event(surface, force, target,
      request.kind == "heavy" and "raid" or request.kind, size, {
        source = source,
        generator = generator,
        stagger = request.stagger,
        forced_kind = request.kind == "heavy" and "heavy" or request.forced_kind
      })
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
  local drone_details = {}
  for unit_number, drone in pairs(surface_state.active_drones) do
    drone_details[#drone_details + 1] = {
      unit_number = unit_number,
      event_id = drone.event_id,
      origin = drone.origin,
      source_unit_number = drone.source_unit_number,
      kind = drone.kind,
      role = drone.role,
      mission = drone.mission,
      via = drone.via,
      position = drone.entity and drone.entity.valid and {x = drone.entity.position.x, y = drone.entity.position.y} or nil,
      target_position = drone.target_position and {x = drone.target_position.x, y = drone.target_position.y} or nil,
      target_valid = drone.target_entity and drone.target_entity.valid or false
    }
  end
  local ballistic_sound_sources = 0
  local missile_details = {}
  for missile_id, missile in pairs(surface_state.active_missiles) do
    local has_sound_source = missile.sound_source and missile.sound_source.valid or false
    if has_sound_source then
      ballistic_sound_sources = ballistic_sound_sources + 1
    end
    missile_details[#missile_details + 1] = {
      id = missile_id,
      position = {x = missile.position.x, y = missile.position.y},
      target_position = missile.target_position,
      duration_ticks = missile.duration,
      eta_seconds = missile.eta_seconds,
      phase = missile.phase,
      class = missile.class,
      origin = missile.origin,
      source_unit_number = missile.source_unit_number,
      warning_seconds = missile.warning_seconds,
      trail_emissions = missile.trail_emissions or 0,
      has_sound_source = has_sound_source,
      previous_position = missile.previous_position and {
        x = missile.previous_position.x, y = missile.previous_position.y} or nil,
      progress = missile.progress or 0,
      step_distance = missile.step_distance or 0,
      distance_to_target = missile.distance_to_target,
      impact_count = missile.impact_count or 0,
      cleanup_count = missile.cleanup_count or 0
    }
  end
  local root = state.root()
  local projectiles = {}
  for id, shot in pairs(surface_state.projectiles) do
    projectiles[#projectiles + 1] = {id = id, kind = shot.kind, position = shot.position,
      start_tick = shot.start_tick, target_missile_id = shot.target_missile_id, missed = shot.missed}
  end
  local warnings = {}
  for id, warning in pairs(surface_state.warning_history) do
    warnings[#warnings + 1] = {id = id, kind = warning.kind, tick = warning.tick, eta = warning.eta,
      direction = warning.direction, position = warning.position, target = warning.target}
  end
  table.sort(warnings, function(a, b) return a.id < b.id end)
  local sources = {}
  for kind, entities in pairs(surface_state.sources) do
    for _, entity in pairs(entities) do
      if entity.valid then
        sources[#sources + 1] = {kind = kind, unit_number = entity.unit_number, position = entity.position}
      end
    end
  end
  local pending = {}
  for id, entry in pairs(surface_state.pending_events) do
    pending[#pending + 1] = {id = id, kind = entry.kind, tick = entry.tick}
  end
  local delivery = alerts.delivery_state(nil)
  local counters = {}
  for name, value in pairs(surface_state.counters) do counters[name] = value end
  local audio_counters = {}
  for name, value in pairs(root.audio_counters) do audio_counters[name] = value end
  return {
    projectiles = projectiles, warnings = warnings, sources = sources, pending = pending,
    schema_version = root.schema_version,
    next_raid_tick = surface_state.next_raid_tick,
    next_ballistic_tick = surface_state.next_ballistic_tick,
    active_drones = #drone_details,
    drones = drone_details,
    active_missiles = #missile_details,
    ballistic_sound_sources = ballistic_sound_sources,
    missiles = missile_details,
    counters = counters,
    audio_counters = audio_counters,
    engagements = surface_state.engagements,
    radar_signals = radar_signals.status(surface_index),
    visuals = visual_effects.status(surface_index),
    alert_delivery = delivery.mode,
    circuit_delivery_enabled = delivery.circuit_enabled,
    global_warning_dispatches = root.alert_counters.global_warning_dispatches or 0,
    helper_tables = {
      alert_sound_events = type(root.alert_sound_events) == "table",
      audio_cooldowns = type(root.audio_cooldowns) == "table",
      radar_relays = type(root.radar_relays) == "table",
      visual_records = type(root.visual_records) == "table"
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

local VALID_DELIVERY = {["both"] = true, ["global-sound"] = true, ["circuit-only"] = true}

local function remote_set_alert_delivery(mode)
  if not VALID_DELIVERY[mode] then
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
        return {ok = false, error = "accuracy-out-of-range"}
      end
      settings.global["shahed-attack-intercept-accuracy"] = {value = value}
      return {ok = true}
    end,
    -- Changes one of this mod's map settings (other mods and scenarios cannot
    -- write them directly). Returns {ok, error}.
    set_setting = function(name, value)
      if type(name) ~= "string" or not name:find("^shahed%-attack%-") or settings.global[name] == nil then
        return {ok = false, error = "unknown-setting"}
      end
      local ok = pcall(function() settings.global[name] = {value = value} end)
      return ok and {ok = true} or {ok = false, error = "invalid-value"}
    end,
    schedule_event = remote_schedule,
    get_surface_state = remote_state,
    get_alert_delivery_state = remote_delivery_state,
    set_alert_delivery = remote_set_alert_delivery,
    clear_threats = function(surface_index)
      local surface_state = state.get_surface(surface_index or 1)
      if not surface_state then return 0 end
      return raids.clear(surface_state) + ballistics.clear(surface_state)
    end,
    start_profiling = profiler.start,
    stop_profiling = profiler.stop
  })
end

return commands_api
