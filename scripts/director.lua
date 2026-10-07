local balance = require("scripts.balance")
local ballistics = require("scripts.ballistics")
local infrastructure = require("scripts.infrastructure")
local random = require("scripts.lib.random")
local raids = require("scripts.raids")
local state = require("scripts.state")
local targeting = require("scripts.targeting")

local rules = require("scripts.lib.air_rules")

local director = {}

local function setting(name, fallback)
  local value = settings.global[name]
  return value and value.value or fallback
end

local function schedule_next_raid(surface, surface_state, generator, tick)
  local multiplier = setting("shahed-attack-raid-frequency-multiplier", 1)
  local days = generator:range_float(0.8, 1.8) / multiplier
  surface_state.next_raid_tick = tick + math.max(60 * 60, math.floor(days * surface.ticks_per_day))
end

local function choose_force_and_target(surface, generator, intelligence)
  local forces = targeting.get_candidate_forces(surface)
  if #forces == 0 then
    return nil, nil
  end
  local force = forces[generator:range_int(1, #forces)]
  return force, targeting.choose(surface, force, generator, intelligence)
end

local function try_raid(surface, surface_state, generator, tick, evolution)
  local intelligence_force
  for force_index, count in pairs(surface_state.intelligence) do
    if count > 0 then
      intelligence_force = force_index
      break
    end
  end
  local has_intelligence = intelligence_force ~= nil
  local force, target = choose_force_and_target(surface, generator, has_intelligence)
  if not force or not target then
    schedule_next_raid(surface, surface_state, generator, tick)
    return
  end

  local source=infrastructure.get_source(surface_state,"airfields",target.position,generator)
  if not source then
    schedule_next_raid(surface,surface_state,generator,tick)
    return
  end
  local kind = balance.choose_event_kind(
    generator:next_float(),
    evolution,
    setting("shahed-attack-recon-enabled", true)
  )
  local intelligence_count = surface_state.intelligence[force.index] or 0
  local intelligence_bonus = intelligence_count > 0 and 1.15 or 1
  local size = balance.raid_size(
    evolution,
    setting("shahed-attack-raid-size-multiplier", 1),
    intelligence_bonus
  )
  if kind == "recon" then
    size = evolution >= 0.6 and 2 or 1
  elseif intelligence_count > 0 then
    surface_state.intelligence[force.index] = intelligence_count - 1
  end
  raids.spawn_event(surface,force,target,kind,size,{source=source,generator=generator})
  schedule_next_raid(surface, surface_state, generator, tick)
end

local function schedule_next_ballistic(surface_state, current_day, generator)
  local multiplier = setting("shahed-attack-ballistic-frequency-multiplier", 1)
  local days = math.max(1, math.floor(generator:range_int(3, 7) / multiplier + 0.5))
  surface_state.next_ballistic_day = current_day + days
end

local function track_readiness(surface,surface_state,tick)
  for _,force in ipairs(targeting.get_candidate_forces(surface)) do
    local chemical=force.technologies["chemical-science-pack"]
    if chemical and chemical.researched and not surface_state.ballistic_readiness[force.index] then
      surface_state.ballistic_readiness[force.index]=tick+rules.BALLISTIC_PREPARATION_TICKS
    end
  end
end

local function try_ballistic(surface, surface_state, generator, current_day, evolution)
  local enabled = setting("shahed-attack-ballistic-enabled", true)
  if not balance.ballistic_eligible(current_day, evolution, enabled)
    or current_day < surface_state.next_ballistic_day then
    return
  end
  local force, target = choose_force_and_target(surface, generator, true)
  if not force or not target then
    surface_state.next_ballistic_day = current_day + 1
    return
  end
  local source = infrastructure.get_source(surface_state, "ballistic_sites", target.position, generator)
  if not surface_state.ballistic_readiness[force.index]
    or game.tick<surface_state.ballistic_readiness[force.index] or not source then
    surface_state.next_ballistic_day = current_day + 1
    return
  end
  ballistics.launch(surface, force, target, source, generator)
  if evolution >= 0.8 and generator:next_float() < 0.20 then
    local second_target = targeting.choose(surface, force, generator, true)
    if second_target and second_target.valid and second_target.unit_number ~= target.unit_number then
      ballistics.launch(surface, force, second_target, source, generator)
    end
  end
  schedule_next_ballistic(surface_state, current_day, generator)
end

function director.initialize()
  for _, surface in pairs(game.surfaces) do
    state.ensure_surface(surface)
  end
end

function director.on_configuration_changed()
  for _, surface in pairs(game.surfaces) do
    local surface_state = state.ensure_surface(surface)
    local current_day = math.floor(game.tick / math.max(surface.ticks_per_day, 1))
    if surface_state.next_raid_tick == nil then
      surface_state.next_raid_tick = game.tick + 2 * surface.ticks_per_day
    end
    if surface_state.next_ballistic_day == nil then
      surface_state.next_ballistic_day = current_day + 2
    end
  end
end

function director.update(tick)
  for _, surface in pairs(game.surfaces) do
    local surface_state = state.ensure_surface(surface)
    local generator = random.new(surface_state.rng_state)
    local current_daytime = surface.daytime
    local peaceful = surface.map_gen_settings.peaceful_mode == true
    local evolution = game.forces.enemy.get_evolution_factor(surface)
    local current_day = math.floor(tick / math.max(surface.ticks_per_day, 1))

    track_readiness(surface,surface_state,tick)
    if not peaceful and tick >= surface_state.next_raid_tick then
      try_raid(surface, surface_state, generator, tick, evolution)
    end

    if not peaceful and balance.crossed_dusk(
      surface_state.last_daytime,
      current_daytime,
      surface.dusk,
      surface.always_day,
      surface.freeze_daytime
    ) then
      try_ballistic(surface, surface_state, generator, current_day, evolution)
    end

    surface_state.last_daytime = current_daytime
    surface_state.rng_state = generator.state
  end
end

return director
