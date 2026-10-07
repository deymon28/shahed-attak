local rules = {
  DRONE_RADAR_RANGE = 384,
  BALLISTIC_RADAR_RANGE = 2048,
  ABM_RANGE = 192,
  ABM_COOLDOWN = 60,
  ABM_ENERGY = 10000000,
  ABM_AIM_TICKS = 10,
  ABM_TURN_RATE = 1 / 60,
  INTERCEPTOR_SPEED = 6,
  INTERCEPT_ACCURACY = 0.70,
  WARNING_HORIZON = 60,
  BALLISTIC_MIN_DAY = 20,
  BALLISTIC_PREPARATION_TICKS = 30 * 60 * 60
}

function rules.incoming_direction(position, target)
  local angle = math.atan2 and math.atan2(position.y - target.y, position.x - target.x)
    or math.atan(position.y - target.y, position.x - target.x)
  local names = {'east','south-east','south','south-west','west','north-west','north','north-east'}
  return names[math.floor(((angle + math.pi / 8) % (math.pi * 2)) / (math.pi / 4)) + 1]
end

function rules.drone_eta(distance, speed)
  return math.max(0, distance - 3) / math.max(speed or 0.08, 0.001) / 60
end

function rules.drone_warning(distance, speed, tracked)
  return (tracked and rules.drone_eta(distance, speed) <= rules.WARNING_HORIZON) or distance <= 50
end

function rules.ballistic_duration(distance)
  -- Bound terminal velocity so entering a radar envelope leaves reaction time.
  return math.ceil(math.max(45, distance / 24) * 60)
end

function rules.ballistic_progress(elapsed, duration)
  local t = math.max(0, math.min(1, elapsed / math.max(duration, 1)))
  return 0.06 * t + 0.94 * t * t
end

function rules.battery_ready(distance, tick, next_shot_tick, energy, ammunition)
  return distance <= rules.ABM_RANGE and tick >= (next_shot_tick or 0)
    and energy >= rules.ABM_ENERGY and ammunition > 0
end

return rules
