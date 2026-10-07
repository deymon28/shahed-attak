local balance = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function balance.raid_size(evolution, size_multiplier, intelligence_bonus)
  local raw = (2 + 4 * (clamp(evolution or 0, 0, 1) ^ 1.3))
    * (size_multiplier or 1)
    * (intelligence_bonus or 1)
  return clamp(math.floor(raw + 0.5), 2, 12)
end

function balance.intercept_probability(tracking, geometry, missile_tier)
  local probability = 0.30
    + 0.30 * clamp(tracking or 0, 0, 1)
    + 0.15 * clamp(geometry or 0, 0, 1)
    - 0.10 * clamp(missile_tier or 0, 0, 1)
  return clamp(probability, 0.25, 0.75)
end

function balance.combined_intercept_probability(probabilities)
  local miss_probability = 1
  for _, probability in ipairs(probabilities or {}) do
    miss_probability = miss_probability * (1 - clamp(probability, 0, 1))
  end
  return 1 - miss_probability
end

function balance.choose_event_kind(roll, evolution, recon_enabled)
  local value = clamp(roll or 0, 0, 1)
  if recon_enabled and value < 0.25 then
    return "recon"
  end
  if (evolution or 0) >= 0.35 and value >= 0.90 then
    return "mixed"
  end
  return "raid"
end

function balance.crash_outcome(kind, roll, evolution)
  local value = clamp(roll or 0, 0, 1)
  if kind == "recon" then
    return value < 0.90 and "safe" or "fuel"
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

function balance.ballistic_eligible(day, evolution, enabled)
  return enabled == true and (day or 0) >= 20 and (evolution or 0) >= 0.35
end

function balance.crossed_dusk(previous_daytime, current_daytime, dusk, always_day, freeze_daytime)
  if always_day or freeze_daytime then
    return false
  end
  return previous_daytime < dusk and current_daytime >= dusk
end

function balance.clamp(value, minimum, maximum)
  return clamp(value, minimum, maximum)
end

return balance
