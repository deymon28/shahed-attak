-- Owns the persistent storage layout. Every module reads its tables through
-- state.root() / state.ensure_surface() so defaults live in one place.
local state = {}

state.SCHEMA_VERSION = 6
-- The air war is fought on the starting planet only.
state.SUPPORTED_SURFACE = "nauvis"

local COUNTERS = {
  "events", "raids", "recon", "ballistic", "intercepted",
  "wreck_safe", "wreck_fuel", "wreck_warhead",
  "ballistic_impacts", "ballistic_cleanups",
  "drones_launched", "decoys_launched", "drones_destroyed", "drone_impacts",
  "interceptor_launches", "interceptor_encounters", "interceptor_misses", "interceptor_drone_hits",
  "flak_shots", "flak_hits", "flak_misses", "sources_generated"
}

local ROOT_TABLES = {
  "surfaces", "alert_sound_events", "pending_alert_sounds", "alert_sound_playback",
  "radar_relays", "radar_relay_registrations", "audio_cooldowns", "audio_counters",
  "targets", "target_registrations", "scan_queue",
  "source_registrations", "source_scan_queue", "source_decisions",
  "defense_registrations", "visual_records", "visual_registrations", "visual_active_launches",
  "range_renders", "range_registrations"
}

local SURFACE_TABLES = {
  "intelligence", "active_drones", "active_missiles", "alerted_events", "warning_history",
  "projectiles", "engagements", "battery_next_shot", "battery_tracking", "battery_modes",
  "launcher_rounds", "wagon_state", "ballistic_readiness", "pending_events"
}

function state.supported(surface)
  return surface ~= nil and surface.valid and surface.name == state.SUPPORTED_SURFACE
end

function state.root()
  storage.shahed_attack = storage.shahed_attack or {}
  local root = storage.shahed_attack
  for _, name in ipairs(ROOT_TABLES) do
    root[name] = root[name] or {}
  end
  root.next_event_id = root.next_event_id or 1
  root.alert_counters = root.alert_counters or {global_warning_dispatches = 0}
  root.visual_counters = root.visual_counters or {ballistic_launches = 0, abm_launches = 0}
  return root
end

local function ensure_surface_fields(surface, surface_state)
  local ticks_per_day = math.max(surface.ticks_per_day, 1)
  surface_state.created_tick = surface_state.created_tick or game.tick
  -- The first raid waits for the grace period setting (director.initialize).
  surface_state.next_raid_tick = surface_state.next_raid_tick or surface_state.created_tick
  surface_state.next_ballistic_tick = surface_state.next_ballistic_tick or (game.tick + math.floor(ticks_per_day / 4))
  surface_state.rng_state = surface_state.rng_state
    or ((surface.map_gen_settings.seed or 1) + surface.index * 7919) % 2147483647
  surface_state.combat_rng_state = surface_state.combat_rng_state or surface_state.rng_state
  for _, name in ipairs(SURFACE_TABLES) do
    surface_state[name] = surface_state[name] or {}
  end
  surface_state.sources = surface_state.sources or {}
  surface_state.sources.airfields = surface_state.sources.airfields or {}
  surface_state.sources.ballistic_sites = surface_state.sources.ballistic_sites or {}
  surface_state.defenses = surface_state.defenses or {}
  for _, name in ipairs({"radars", "aa_turrets", "abm_batteries", "aa_wagons", "abm_wagons"}) do
    surface_state.defenses[name] = surface_state.defenses[name] or {}
  end
  surface_state.counters = surface_state.counters or {}
  for _, name in ipairs(COUNTERS) do
    surface_state.counters[name] = surface_state.counters[name] or 0
  end
end

-- Returns nil for surfaces outside the air war.
function state.ensure_surface(surface)
  if not state.supported(surface) then
    return nil
  end
  local root = state.root()
  local surface_state = root.surfaces[surface.index]
  if not surface_state then
    surface_state = {}
    root.surfaces[surface.index] = surface_state
  end
  ensure_surface_fields(surface, surface_state)
  return surface_state
end

function state.get_surface(surface_index)
  return storage.shahed_attack and storage.shahed_attack.surfaces
    and storage.shahed_attack.surfaces[surface_index]
end

function state.initialize()
  state.root()
  for _, surface in pairs(game.surfaces) do
    state.ensure_surface(surface)
  end
end

function state.next_event_id()
  local root = state.root()
  local result = root.next_event_id
  root.next_event_id = result + 1
  return result
end

-- Drops warning diagnostics ten minutes after their event ended.
function state.prune(tick)
  for _, current in pairs(state.root().surfaces) do
    local active = {}
    for _, drone in pairs(current.active_drones) do active[drone.event_id] = true end
    for id in pairs(current.active_missiles) do active[id] = true end
    for _, pending in pairs(current.pending_events) do
      if pending.event_id then active[pending.event_id] = true end
    end
    for id, warning in pairs(current.warning_history) do
      if not active[id] and tick - warning.tick > 60 * 60 * 10 then
        current.warning_history[id] = nil
        current.alerted_events[id] = nil
      end
    end
  end
end

-- Forget everything that belonged to a deleted surface.
function state.forget_surface(surface_index)
  local root = state.root()
  root.surfaces[surface_index] = nil
  root.targets[surface_index] = nil
  root.scan_queue[surface_index] = nil
  root.source_scan_queue[surface_index] = nil
  root.source_decisions[surface_index] = nil
  root.audio_cooldowns[surface_index] = nil
  for _, map_name in ipairs({"target_registrations", "source_registrations", "defense_registrations"}) do
    for registration, record in pairs(root[map_name]) do
      if record.surface_index == surface_index then root[map_name][registration] = nil end
    end
  end
end

-- Carries per-force planning state over to the force that absorbed another.
function state.merge_forces(source_index, destination_index)
  for _, current in pairs(state.root().surfaces) do
    local intelligence = current.intelligence[source_index]
    if intelligence then
      current.intelligence[destination_index] = math.max(current.intelligence[destination_index] or 0, intelligence)
      current.intelligence[source_index] = nil
    end
    local readiness = current.ballistic_readiness[source_index]
    if readiness then
      current.ballistic_readiness[destination_index] = math.min(current.ballistic_readiness[destination_index] or readiness, readiness)
      current.ballistic_readiness[source_index] = nil
    end
    for _, drone in pairs(current.active_drones) do
      if drone.target_force_index == source_index then drone.target_force_index = destination_index end
    end
    for _, missile in pairs(current.active_missiles) do
      if missile.force_index == source_index then missile.force_index = destination_index end
    end
    for _, shot in pairs(current.projectiles) do
      if shot.force_index == source_index then shot.force_index = destination_index end
    end
    for _, pending in pairs(current.pending_events) do
      if pending.force_index == source_index then pending.force_index = destination_index end
      if pending.group and pending.group.force_index == source_index then pending.group.force_index = destination_index end
    end
  end
end

-- One-time conversion of schema 5 (and older) tables.
function state.migrate()
  local root = state.root()
  local previous = root.schema_version or 1
  if previous < 6 then
    -- Target records keep their unit numbers; targeting.initialize compacts the lists.
    if root.destroyed_registrations then
      root.target_registrations = root.destroyed_registrations
    end
    root.destroyed_registrations = nil
    -- Registrations are recreated by the module initializers with unit numbers.
    root.source_registrations = {}
    root.defense_registrations = {}
    for surface_index, current in pairs(root.surfaces) do
      local surface = game.get_surface(surface_index)
      if not state.supported(surface) then
        root.surfaces[surface_index] = nil
      else
        -- Lists with `false` holes become maps keyed by unit number.
        for _, group in pairs({current.sources or {}, current.defenses or {}}) do
          for name, list in pairs(group) do
            local keyed = {}
            for _, entity in pairs(list) do
              if entity and entity.valid and entity.unit_number then keyed[entity.unit_number] = entity end
            end
            group[name] = keyed
          end
        end
        if current.next_ballistic_day and not current.next_ballistic_tick then
          current.next_ballistic_tick = math.max(game.tick,
            math.floor(current.next_ballistic_day * math.max(surface.ticks_per_day, 1)))
        end
        current.next_ballistic_day = nil
        current.last_daytime = nil
        -- Readiness used to store the preparation deadline (chemistry + 30 min);
        -- it now stores the chemistry tick so the preparation time is a setting.
        for force_index, deadline in pairs(current.ballistic_readiness or {}) do
          current.ballistic_readiness[force_index] = math.max(0, deadline - 30 * 60 * 60)
        end
        for _, missile in pairs(current.active_missiles or {}) do
          -- Missiles launched before classes existed carry the full warhead.
          missile.class = missile.class or "heavy"
          missile.tier = nil
          missile.attempted_batteries = nil
          missile.probabilities = nil
        end
      end
    end
  end
  root.schema_version = state.SCHEMA_VERSION
end

return state
