local state = {}

local SCHEMA_VERSION = 5

local function ensure_counters(surface_state)
  surface_state.counters = surface_state.counters or {}
  for _, name in ipairs({
    "events", "raids", "recon", "ballistic", "intercepted",
    "wreck_safe", "wreck_fuel", "wreck_warhead",
    "ballistic_impacts", "ballistic_cleanups"
  }) do
    surface_state.counters[name] = surface_state.counters[name] or 0
  end
end

local function ensure_root()
  storage.shahed_attack = storage.shahed_attack or {}
  local root = storage.shahed_attack
  root.schema_version = SCHEMA_VERSION
  root.surfaces = root.surfaces or {}
  root.registration_owners = root.registration_owners or {}
  root.next_event_id = root.next_event_id or 1
  root.alert_sound_events = root.alert_sound_events or {}
  root.alert_counters = root.alert_counters or {global_warning_dispatches = 0}
  root.radar_relays = root.radar_relays or {}
  root.radar_relay_registrations = root.radar_relay_registrations or {}
  root.audio_cooldowns = root.audio_cooldowns or {}
  root.audio_counters = root.audio_counters or {}
  root.source_registrations = root.source_registrations or {}
  root.source_scan_queue = root.source_scan_queue or {}
  root.defense_registrations = root.defense_registrations or {}
  root.visual_records = root.visual_records or {}
  root.visual_registrations = root.visual_registrations or {}
  root.visual_counters = root.visual_counters or {ballistic_launches = 0, abm_launches = 0}
  return root
end

local function ensure_surface_fields(surface, surface_state)
  local ticks_per_day = math.max(surface.ticks_per_day, 1)
  local current_day = math.floor(game.tick / ticks_per_day)
  if surface_state.created_tick == nil then surface_state.created_tick = game.tick end
  if surface_state.next_raid_tick == nil then surface_state.next_raid_tick = game.tick + 2 * ticks_per_day end
  if surface_state.next_ballistic_day == nil then
    surface_state.next_ballistic_day = math.max(20, current_day + 2)
  end
  if surface_state.last_daytime == nil then surface_state.last_daytime = surface.daytime end
  if surface_state.rng_state == nil then
    surface_state.rng_state = ((surface.map_gen_settings.seed or 1) + surface.index * 7919) % 2147483647
  end
  surface_state.intelligence = surface_state.intelligence or {}
  surface_state.active_drones = surface_state.active_drones or {}
  surface_state.active_missiles = surface_state.active_missiles or {}
  surface_state.alerted_events = surface_state.alerted_events or {}
  surface_state.sources = surface_state.sources or {}
  surface_state.sources.airfields = surface_state.sources.airfields or {}
  surface_state.sources.ballistic_sites = surface_state.sources.ballistic_sites or {}
  surface_state.defenses = surface_state.defenses or {}
  surface_state.defenses.radars = surface_state.defenses.radars or {}
  surface_state.defenses.aa_turrets = surface_state.defenses.aa_turrets or {}
  surface_state.defenses.abm_batteries = surface_state.defenses.abm_batteries or {}
  surface_state.projectiles = surface_state.projectiles or {}
  surface_state.battery_next_shot = surface_state.battery_next_shot or {}
  surface_state.combat_rng_state = surface_state.combat_rng_state or surface_state.rng_state
  surface_state.warning_history = surface_state.warning_history or {}
  surface_state.ballistic_readiness = surface_state.ballistic_readiness or {}
  ensure_counters(surface_state)
  for _, missile in pairs(surface_state.active_missiles) do
    missile.position = missile.position or missile.origin or missile.target_position
    missile.previous_position = missile.previous_position or {
      x = missile.position.x,
      y = missile.position.y
    }
    missile.progress = missile.progress or 0
    missile.step_distance = missile.step_distance or 0
    if missile.distance_to_target == nil and missile.target_position then
      local dx = missile.position.x - missile.target_position.x
      local dy = missile.position.y - missile.target_position.y
      missile.distance_to_target = math.sqrt(dx * dx + dy * dy)
    end
    missile.impact_count = missile.impact_count or 0
    missile.cleanup_count = missile.cleanup_count or 0
    missile.attempted_batteries = missile.attempted_batteries or {}
    missile.probabilities = missile.probabilities or {}
    missile.trail_emissions = missile.trail_emissions or 0
  end
end

local function new_surface_state(surface)
  local ticks_per_day = math.max(surface.ticks_per_day, 1)
  local current_day = math.floor(game.tick / ticks_per_day)
  return {
    created_tick = game.tick,
    next_raid_tick = game.tick + 2 * ticks_per_day,
    next_ballistic_day = math.max(20, current_day + 2),
    last_daytime = surface.daytime,
    rng_state = ((surface.map_gen_settings.seed or 1) + surface.index * 7919) % 2147483647,
    intelligence = {},
    active_drones = {},
    active_missiles = {},
    alerted_events = {},
    sources = {airfields = {}, ballistic_sites = {}},
    defenses = {radars = {}, aa_turrets = {}, abm_batteries = {}},
    counters = {
      events = 0,
      raids = 0,
      recon = 0,
      ballistic = 0,
      intercepted = 0,
      wreck_safe = 0,
      wreck_fuel = 0,
      wreck_warhead = 0,
      ballistic_impacts = 0,
      ballistic_cleanups = 0
    }
  }
end

function state.ensure_surface(surface)
  local root = ensure_root()
  if not root.surfaces[surface.index] then
    root.surfaces[surface.index] = new_surface_state(surface)
  end
  local surface_state = root.surfaces[surface.index]
  ensure_surface_fields(surface, surface_state)
  return surface_state
end

function state.prune(tick)
  for _, current in pairs(storage.shahed_attack.surfaces) do
    local active = {}
    for _, drone in pairs(current.active_drones) do active[drone.event_id] = true end
    for id in pairs(current.active_missiles) do active[id] = true end
    for id, warning in pairs(current.warning_history) do
      if not active[id] and tick - warning.tick > 60 * 60 * 10 then
        current.warning_history[id] = nil
        current.alerted_events[id] = nil
      end
    end
  end
end

function state.initialize()
  local root = ensure_root()
  for _, surface in pairs(game.surfaces) do
    state.ensure_surface(surface)
  end
end

function state.get_surface(surface_index)
  return storage.shahed_attack and storage.shahed_attack.surfaces[surface_index]
end

function state.next_event_id()
  local root = ensure_root()
  local result = root.next_event_id
  root.next_event_id = result + 1
  return result
end

return state
