-- Plans natural attacks. Threat grows with enemy evolution: drone raids
-- become mass raids with decoys and defense suppression; ballistic strikes
-- start as rare, inaccurate light missiles and grow into heavy salvos.
local balance = require("scripts.balance")
local ballistics = require("scripts.ballistics")
local config = require("scripts.lib.config")
local defense = require("scripts.defense")
local infrastructure = require("scripts.infrastructure")
local random = require("scripts.lib.random")
local raids = require("scripts.raids")
local rules = require("scripts.lib.air_rules")
local state = require("scripts.state")
local targeting = require("scripts.targeting")

local director = {}

local DRONE_SPEED_TILES_PER_TICK = 0.08
local AA_NAMES = {["shahed-attack-aa-turret"] = true, ["shahed-attack-aa-wagon"] = true}

local function ticks_per_day(surface)
  return math.max(surface.ticks_per_day, 1)
end

local function evolution_of(surface)
  return game.forces.enemy.get_evolution_factor(surface)
end

local function schedule_next_raid(surface, surface_state, generator, tick, evolution)
  local days = balance.raid_interval_days(evolution, generator:next_float(),
    config.global("shahed-attack-raid-frequency-multiplier"))
  surface_state.next_raid_tick = tick + math.max(60 * 60, math.floor(days * ticks_per_day(surface)))
end

local function choose_force_and_target(surface, generator, intelligence)
  local candidates = targeting.get_candidate_forces(surface)
  if #candidates == 0 then
    return nil, nil
  end
  local force = candidates[generator:range_int(1, #candidates)]
  return force, targeting.choose(surface, force, generator, intelligence)
end

-- Ballistic availability -----------------------------------------------------

-- ballistic_readiness[force] holds the tick chemical science was first seen.
local function track_readiness(surface, surface_state, tick)
  for _, force in ipairs(targeting.get_candidate_forces(surface)) do
    local chemical = force.technologies["chemical-science-pack"]
    if chemical and chemical.researched and not surface_state.ballistic_readiness[force.index] then
      surface_state.ballistic_readiness[force.index] = tick
    end
  end
end

function director.ballistic_progress(surface)
  return balance.progress(evolution_of(surface), config.global("shahed-attack-ballistic-start-evolution"))
end

-- Returns true, or false plus the first unmet requirement.
function director.ballistic_available(surface, surface_state, force, tick)
  if not config.global("shahed-attack-ballistic-enabled") then
    return false, "disabled"
  end
  local day = tick / ticks_per_day(surface)
  if not balance.ballistic_eligible(day, evolution_of(surface), true,
    config.global("shahed-attack-ballistic-start-day"),
    config.global("shahed-attack-ballistic-start-evolution")) then
    return false, "calendar"
  end
  local chemistry_tick = force and surface_state.ballistic_readiness[force.index]
  if not chemistry_tick then
    return false, "chemistry"
  end
  local preparation = config.global("shahed-attack-ballistic-preparation-minutes") * 3600
  if tick < chemistry_tick + preparation then
    return false, "preparation"
  end
  return true
end

-- Ballistic salvos -------------------------------------------------------------

local function queue(surface_state, entry)
  surface_state.pending_events[state.next_event_id()] = entry
end

-- Launches a salvo: the first missile now, the rest a few seconds apart from
-- the available launch sites. delay_ticks postpones the whole salvo.
local function launch_salvo(surface, surface_state, force, target, generator, size, delay_ticks)
  local sites = infrastructure.sources_in_range(surface_state, "ballistic_sites", target.position)
  if #sites == 0 then
    return 0
  end
  local class = rules.ballistic_class(director.ballistic_progress(surface))
  local salvo_id = state.next_event_id()
  local used = {[target.unit_number] = true}
  local launch_tick = game.tick + (delay_ticks or 0)
  local launched = 0
  for index = 1, size do
    local missile_target = target
    if index > 1 then
      local distinct = targeting.choose_distinct_near_position(surface, force, target.position, 96, used, generator)
      if distinct then
        missile_target = distinct
        used[distinct.unit_number] = true
      end
    end
    local site = sites[(index - 1) % #sites + 1]
    if index == 1 and launch_tick <= game.tick then
      if ballistics.launch(surface, force, missile_target, site, generator, {class = class, salvo_id = salvo_id}) then
        launched = launched + 1
      end
    else
      launch_tick = launch_tick + (index > 1 and generator:range_int(60, 240) or 0)
      queue(surface_state, {tick = launch_tick, kind = "ballistic", force_index = force.index,
        target = missile_target, site = site, class = class, salvo_id = salvo_id})
      launched = launched + 1
    end
  end
  return launched
end

local function try_ballistic(surface, surface_state, generator, tick)
  local force, target = choose_force_and_target(surface, generator, true)
  local retry = math.floor(ticks_per_day(surface) / 4)
  if not force or not target then
    surface_state.next_ballistic_tick = tick + retry
    return
  end
  if not director.ballistic_available(surface, surface_state, force, tick) then
    surface_state.next_ballistic_tick = tick + retry
    return
  end
  local progress = director.ballistic_progress(surface)
  local size = balance.ballistic_salvo(progress, config.global("shahed-attack-max-ballistic-salvo"),
    generator:next_float())
  if launch_salvo(surface, surface_state, force, target, generator, size, 0) == 0 then
    surface_state.next_ballistic_tick = tick + ticks_per_day(surface)
    return
  end
  local days = balance.ballistic_interval_days(progress, generator:next_float(),
    config.global("shahed-attack-ballistic-frequency-multiplier"))
  surface_state.next_ballistic_tick = tick + math.max(60 * 60, math.floor(days * ticks_per_day(surface)))
end

-- Drone raids --------------------------------------------------------------------

-- Known defenses near the target: AA guns and drone-capable ABM launchers.
local function known_defenses(surface, force, target)
  local aa, abm = 0, 0
  for _, entity in ipairs(targeting.find_defenses(surface, force, target.position, rules.ABM_RANGE)) do
    local distance_sq = (entity.position.x - target.position.x) ^ 2 + (entity.position.y - target.position.y) ^ 2
    if AA_NAMES[entity.name] then
      if distance_sq <= 64 * 64 then aa = aa + 1 end
    elseif defense.is_abm_launcher(entity) and defense.get_mode(entity) ~= "ballistic" then
      abm = abm + 1
    end
  end
  return aa, abm
end

-- Some raids are combined with a missile salvo timed to arrive with the drones.
local function maybe_combined_strike(surface, surface_state, force, target, source, generator, tick)
  if not director.ballistic_available(surface, surface_state, force, tick) then
    return
  end
  local progress = director.ballistic_progress(surface)
  if generator:next_float() >= balance.combined_strike_chance(progress) then
    return
  end
  local sites = infrastructure.sources_in_range(surface_state, "ballistic_sites", target.position)
  if #sites == 0 then
    return
  end
  local dx, dy = source.position.x - target.position.x, source.position.y - target.position.y
  local drone_ticks = math.sqrt(dx * dx + dy * dy) / DRONE_SPEED_TILES_PER_TICK
  local sx, sy = sites[1].position.x - target.position.x, sites[1].position.y - target.position.y
  local missile_ticks = rules.ballistic_duration(math.sqrt(sx * sx + sy * sy), rules.ballistic_class(progress))
  local size = math.max(1, math.floor(balance.ballistic_salvo(progress,
    config.global("shahed-attack-max-ballistic-salvo"), generator:next_float()) / 2))
  launch_salvo(surface, surface_state, force, target, generator, size, math.max(0, math.floor(drone_ticks - missile_ticks)))
end

local function first_intelligence(surface_state)
  for _, count in pairs(surface_state.intelligence) do
    if count > 0 then return true end
  end
  return false
end

local function try_raid(surface, surface_state, generator, tick, evolution)
  local has_intelligence = first_intelligence(surface_state)
  local force, target = choose_force_and_target(surface, generator, has_intelligence)
  if not force or not target then
    schedule_next_raid(surface, surface_state, generator, tick, evolution)
    return
  end
  local sources = infrastructure.sources_in_range(surface_state, "airfields", target.position)
  if #sources == 0 then
    schedule_next_raid(surface, surface_state, generator, tick, evolution)
    return
  end
  local recon_enabled = config.global("shahed-attack-recon-enabled")
  local intelligence_count = surface_state.intelligence[force.index] or 0
  local kind = balance.choose_event_kind(generator:next_float(), evolution, recon_enabled, intelligence_count > 0)
  local size
  if kind == "recon" then
    size = evolution >= 0.6 and 2 or 1
  else
    local defense_bonus = 0
    if config.global("shahed-attack-adaptive-raids-enabled") and (intelligence_count > 0 or evolution >= 0.7) then
      defense_bonus = balance.adaptive_bonus(known_defenses(surface, force, target))
    end
    size = balance.raid_size(evolution, config.global("shahed-attack-raid-size-multiplier"),
      intelligence_count > 0 and 1.15 or 1, defense_bonus, config.global("shahed-attack-max-raid-size"))
    if intelligence_count > 0 then
      surface_state.intelligence[force.index] = intelligence_count - 1
    end
  end
  local event_id = raids.spawn_event(surface, force, target, kind, size, {sources = sources, generator = generator})
  if event_id and kind ~= "recon" then
    maybe_combined_strike(surface, surface_state, force, target, sources[1], generator, tick)
  end
  schedule_next_raid(surface, surface_state, generator, tick, evolution)
end

-- Lifecycle -------------------------------------------------------------------------

function director.initialize()
  for _, surface in pairs(game.surfaces) do
    local surface_state = state.ensure_surface(surface)
    if surface_state and not surface_state.grace_applied then
      -- New worlds wait for the configured grace period before the first raid.
      surface_state.next_raid_tick = math.max(surface_state.next_raid_tick,
        surface_state.created_tick + math.floor(config.global("shahed-attack-grace-period-days") * ticks_per_day(surface)))
      surface_state.grace_applied = true
    end
  end
end

director.on_configuration_changed = director.initialize

function director.update(tick)
  for surface_index, surface_state in pairs(state.root().surfaces) do
    local surface = game.get_surface(surface_index)
    -- surface.peaceful_mode is the live value (it can be changed during a game).
    if state.supported(surface) and not surface.peaceful_mode then
      local generator = random.new(surface_state.rng_state)
      local evolution = evolution_of(surface)
      track_readiness(surface, surface_state, tick)
      local grace_end = surface_state.created_tick
        + math.floor(config.global("shahed-attack-grace-period-days") * ticks_per_day(surface))
      if tick >= surface_state.next_raid_tick and tick >= grace_end then
        try_raid(surface, surface_state, generator, tick, evolution)
      end
      if tick >= surface_state.next_ballistic_tick then
        try_ballistic(surface, surface_state, generator, tick)
      end
      surface_state.rng_state = generator.state
    end
  end
end

-- Queued drone groups and salvo missiles.
function director.process_pending(tick)
  for surface_index, surface_state in pairs(state.root().surfaces) do
    if next(surface_state.pending_events) then
      local surface = game.get_surface(surface_index)
      local due = {}
      for id, pending in pairs(surface_state.pending_events) do
        if tick >= pending.tick then due[#due + 1] = id end
      end
      if #due > 0 and surface then
        table.sort(due)
        local generator = random.new(surface_state.rng_state)
        for _, id in ipairs(due) do
          local pending = surface_state.pending_events[id]
          surface_state.pending_events[id] = nil
          if pending.kind == "drone-group" then
            raids.launch_pending_group(surface, surface_state, pending, generator)
          elseif pending.kind == "ballistic" then
            local force = game.forces[pending.force_index]
            local target = pending.target
            if force and not (target and target.valid) then
              target = targeting.choose(surface, force, generator, true)
            end
            local site = pending.site
            if target and not (site and site.valid) then
              site = infrastructure.get_source(surface_state, "ballistic_sites", target.position, generator)
            end
            if force and target and site then
              ballistics.launch(surface, force, target, site, generator,
                {class = pending.class, salvo_id = pending.salvo_id})
            end
          end
        end
        surface_state.rng_state = generator.state
      end
    end
  end
end

-- Seconds until the next scheduled raid and ballistic attempt (for the UI).
function director.schedule(surface, surface_state)
  local tick = game.tick
  local grace_end = surface_state.created_tick
    + math.floor(config.global("shahed-attack-grace-period-days") * ticks_per_day(surface))
  return {
    raid_seconds = math.max(0, math.max(surface_state.next_raid_tick, grace_end) - tick) / 60,
    ballistic_seconds = math.max(0, surface_state.next_ballistic_tick - tick) / 60
  }
end

-- Plans an admin/remote salvo with the natural class progression.
function director.launch_salvo(surface, surface_state, force, target, generator, size, site)
  if site then
    local class = rules.ballistic_class(director.ballistic_progress(surface))
    local salvo_id = state.next_event_id()
    local id = ballistics.launch(surface, force, target, site, generator, {class = class, salvo_id = salvo_id})
    local launched = id and 1 or 0
    for _ = 2, size do
      queue(surface_state, {tick = game.tick + generator:range_int(60, 240), kind = "ballistic",
        force_index = force.index, target = target, site = site, class = class, salvo_id = salvo_id})
      launched = launched + 1
    end
    return launched, id
  end
  return launch_salvo(surface, surface_state, force, target, generator, size, 0)
end

return director
