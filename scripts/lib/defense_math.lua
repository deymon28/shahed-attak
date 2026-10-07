local defense_math = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

function defense_math.distance(a, b)
  return distance(a, b)
end

function defense_math.geometry_score(origin, target, battery, minimum_impact_distance, maximum_cross_track)
  if distance(target, battery) < (minimum_impact_distance or 0) then
    return 0
  end
  local dx = target.x - origin.x
  local dy = target.y - origin.y
  local length_squared = dx * dx + dy * dy
  if length_squared == 0 then
    return 0
  end
  local projection = ((battery.x - origin.x) * dx + (battery.y - origin.y) * dy) / length_squared
  if projection <= 0 or projection >= 1 then
    return 0
  end
  local nearest = {x = origin.x + projection * dx, y = origin.y + projection * dy}
  local cross_track = distance(battery, nearest)
  return clamp(1 - cross_track / math.max(maximum_cross_track or 1, 1), 0, 1)
end

function defense_math.lerp(a, b, amount)
  return {
    x = a.x + (b.x - a.x) * amount,
    y = a.y + (b.y - a.y) * amount
  }
end

return defense_math
