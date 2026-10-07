local defense_math = {}

local function distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

function defense_math.distance(a, b)
  return distance(a, b)
end

function defense_math.lerp(a, b, amount)
  return {
    x = a.x + (b.x - a.x) * amount,
    y = a.y + (b.y - a.y) * amount
  }
end

return defense_math
