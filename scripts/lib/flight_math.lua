local flight_math = {}

local function rotate(vector, angle)
  local cosine = math.cos(angle or 0)
  local sine = math.sin(angle or 0)
  return {
    x = vector.x * cosine - vector.y * sine,
    y = vector.x * sine + vector.y * cosine
  }
end

function flight_math.normalized_motion(previous_position, current_position, fallback_orientation)
  local dx = current_position.x - previous_position.x
  local dy = current_position.y - previous_position.y
  local length = math.sqrt(dx * dx + dy * dy)
  if length > 0.0001 then
    return {x = dx / length, y = dy / length}
  end
  local angle = (fallback_orientation or 0) * math.pi * 2
  return {x = math.sin(angle), y = -math.cos(angle)}
end

function flight_math.project_forward(position, direction, distance, deviation)
  local projected_direction = rotate(direction, deviation or 0)
  return {
    x = position.x + projected_direction.x * distance,
    y = position.y + projected_direction.y * distance
  }
end

function flight_math.direction_index(vector, directions)
  local angle = math.atan2 and math.atan2(vector.y, vector.x) or math.atan(vector.y, vector.x)
  local orientation = ((angle / (math.pi * 2)) + 0.25) % 1
  return math.floor(orientation * directions + 0.5) % directions
end

function flight_math.orientation(origin, target)
  local dx = target.x - origin.x
  local dy = target.y - origin.y
  local angle = math.atan2 and math.atan2(dx, -dy) or math.atan(dx, -dy)
  return (angle / (math.pi * 2)) % 1
end

function flight_math.orbit_point(center, radius_x, radius_y, angle)
  return {
    x = center.x + math.cos(angle) * radius_x,
    y = center.y + math.sin(angle) * radius_y
  }
end

function flight_math.lerp_clamped(origin, target, elapsed_ticks, duration_ticks)
  local duration = math.max(1, duration_ticks)
  local progress = math.max(0, math.min(1, elapsed_ticks / duration))
  return {
    x = origin.x + (target.x - origin.x) * progress,
    y = origin.y + (target.y - origin.y) * progress
  }, progress
end

return flight_math
