-- Threat progression: how often, how large and with what composition the
-- enemy attacks. Pure functions; random rolls are passed in.
local balance = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function lerp(a, b, amount)
  return a + (b - a) * clamp(amount, 0, 1)
end

balance.RAID_GROUP_SIZE = 8

-- 0 at the configured start evolution, 1 at full evolution.
function balance.progress(evolution, start)
  evolution = clamp(evolution or 0, 0, 1)
  start = clamp(start or 0, 0, 1)
  if start >= 1 then
    return evolution >= 1 and 1 or 0
  end
  return clamp((evolution - start) / (1 - start), 0, 1)
end

function balance.raid_interval_days(evolution, roll, multiplier)
  local days = lerp(1.6, 0.6, evolution or 0) * (0.75 + 0.5 * clamp(roll or 0.5, 0, 1))
  return days / math.max(multiplier or 1, 0.01)
end

-- Raids grow from small groups into mass attacks. Known defenses near the
-- target (from reconnaissance) add aircraft so that they can be saturated.
function balance.raid_size(evolution, size_multiplier, intelligence_bonus, defense_bonus, maximum)
  local base = 2 + 22 * (clamp(evolution or 0, 0, 1) ^ 1.4)
  local raw = base * (size_multiplier or 1) * (intelligence_bonus or 1) + (defense_bonus or 0)
  return clamp(math.floor(raw + 0.5), 2, math.max(2, maximum or 40))
end

function balance.adaptive_bonus(aa_count, abm_count)
  return (aa_count or 0) * 1.5 + (abm_count or 0) * 2
end

function balance.group_count(size)
  return math.max(1, math.ceil((size or 1) / balance.RAID_GROUP_SIZE))
end

function balance.choose_event_kind(roll, evolution, recon_enabled, has_intelligence)
  local value = clamp(roll or 0, 0, 1)
  local recon_chance = has_intelligence and 0.10 or 0.30
  if recon_enabled and value < recon_chance then
    return "recon"
  end
  if recon_enabled and (evolution or 0) >= 0.35 and value >= 0.85 then
    return "mixed"
  end
  return "raid"
end

function balance.heavy_share(evolution)
  local e = evolution or 0
  return e >= 0.45 and math.min(0.30, (e - 0.45) * 0.55) or 0
end

-- Cheap decoys imitate strike drones and soak up interceptors and flak.
function balance.decoy_share(evolution, enabled)
  local e = evolution or 0
  if not enabled or e < 0.3 then
    return 0
  end
  return math.min(0.4, (e - 0.3) * 0.8)
end

-- Part of the strike aircraft is sent against air-defense positions.
function balance.suppression_share(evolution, enabled)
  local e = evolution or 0
  if not enabled or e < 0.5 then
    return 0
  end
  return math.min(0.3, (e - 0.5) * 0.6)
end

function balance.drone_kind(event_kind, slot, evolution, roll, decoys_enabled)
  if event_kind == "recon" then
    return "recon"
  end
  if event_kind == "mixed" and slot == 1 then
    return "recon"
  end
  local decoy = balance.decoy_share(evolution, decoys_enabled)
  if roll < decoy then
    return "decoy"
  end
  if roll < decoy + balance.heavy_share(evolution) then
    return "heavy"
  end
  return "strike"
end

function balance.ballistic_salvo(progress, maximum, roll)
  local size = 1 + clamp(progress or 0, 0, 1) * ((maximum or 8) - 1) * (0.5 + 0.5 * clamp(roll or 0, 0, 1))
  return clamp(math.floor(size + 0.5), 1, math.max(1, maximum or 8))
end

function balance.ballistic_interval_days(progress, roll, multiplier)
  local days = lerp(3, 0.8, progress or 0) * (0.8 + 0.4 * clamp(roll or 0.5, 0, 1))
  return days / math.max(multiplier or 1, 0.01)
end

-- Drones and missiles timed to arrive together overload the defense.
function balance.combined_strike_chance(progress)
  local p = progress or 0
  return p >= 0.3 and math.min(0.45, p * 0.45) or 0
end

function balance.crash_outcome(kind, roll, evolution)
  local value = clamp(roll or 0, 0, 1)
  if kind == "recon" then
    return value < 0.90 and "safe" or "fuel"
  end
  if kind == "decoy" then
    return value < 0.95 and "safe" or "fuel"
  end
  local warhead_chance = 0.10
  if kind == "heavy" then
    warhead_chance = 0.10 + 0.10 * clamp(evolution or 0, 0, 1)
  end
  if value >= 1 - warhead_chance then
    return "warhead"
  end
  if value >= 0.60 then
    return "fuel"
  end
  return "safe"
end

-- Ballistics need a calendar day, an evolution level and the per-force
-- preparation window after chemical science.
function balance.ballistic_eligible(day, evolution, enabled, start_day, start_evolution)
  return enabled == true and (day or 0) >= (start_day or 12) and (evolution or 0) >= (start_evolution or 0.25)
end

balance.clamp = clamp
balance.lerp = lerp

return balance
