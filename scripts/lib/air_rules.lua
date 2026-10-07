-- Engagement constants, flight profiles and detection rules.
local rules = {
  DRONE_RADAR_RANGE = 384,
  BALLISTIC_RADAR_RANGE = 2048,
  WARNING_HORIZON = 60,

  AA_TURRET_RANGE = 36,
  AA_WAGON_RANGE = 30,
  AA_WAGON_COOLDOWN = 30,
  AA_WAGON_TURN_RATE = 1 / 40,
  FLAK_MAGAZINE_ROUNDS = 10,

  ABM_RANGE = 192,
  ABM_WAGON_RANGE = 128,
  -- Launches from one launcher are at least this far apart (a two-round salvo
  -- leaves the rails within one second).
  ABM_COOLDOWN = 30,
  -- Ready canisters per launcher; each spent canister takes ABM_RELOAD_TICKS
  -- to replace from the launcher's ammunition inventory.
  ABM_MAGAZINE = 4,
  ABM_RELOAD_TICKS = 600,
  ABM_ENERGY = 10000000,
  ABM_AIM_TICKS = 10,
  ABM_TURN_RATE = 1 / 60,
  INTERCEPTOR_SPEED = 6,
  INTERCEPT_ACCURACY = 0.70,
  -- Hit-probability factors applied to the configured interceptor accuracy.
  DRONE_HIT_FACTOR = 1.15
}

-- Ballistic missile classes unlocked by threat progression.
-- damage/radius scale the heavy warhead; cep is the aim error in tiles.
rules.BALLISTIC_CLASSES = {
  light = {damage = 0.35, radius = 0.65, cep = 10, min_seconds = 50, speed = 20, hit_factor = 1.15, scale = 0.6},
  medium = {damage = 0.7, radius = 0.85, cep = 6, min_seconds = 45, speed = 24, hit_factor = 1.0, scale = 0.75},
  heavy = {damage = 1.0, radius = 1.0, cep = 3, min_seconds = 38, speed = 30, hit_factor = 0.8, scale = 0.9}
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function atan2(y, x)
  return math.atan2 and math.atan2(y, x) or math.atan(y, x)
end

function rules.incoming_direction(position, target)
  local angle = atan2(position.y - target.y, position.x - target.x)
  local names = {"east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"}
  return names[math.floor(((angle + math.pi / 8) % (math.pi * 2)) / (math.pi / 4)) + 1]
end

function rules.drone_eta(distance, speed)
  return math.max(0, distance - 3) / math.max(speed or 0.08, 0.001) / 60
end

function rules.drone_warning(distance, speed, tracked)
  return (tracked and rules.drone_eta(distance, speed) <= rules.WARNING_HORIZON) or distance <= 50
end

function rules.ballistic_class(progress)
  if progress >= 0.7 then
    return "heavy"
  elseif progress >= 0.35 then
    return "medium"
  end
  return "light"
end

function rules.class_stats(class)
  return rules.BALLISTIC_CLASSES[class] or rules.BALLISTIC_CLASSES.heavy
end

-- Missiles fly at least min_seconds so a radar envelope leaves reaction time.
function rules.ballistic_duration(distance, class)
  local stats = rules.BALLISTIC_CLASSES[class or "medium"]
  return math.ceil(math.max(stats.min_seconds, distance / stats.speed) * 60)
end

function rules.ballistic_progress(elapsed, duration)
  local t = clamp(elapsed / math.max(duration, 1), 0, 1)
  return 0.06 * t + 0.94 * t * t
end

-- Uniform point inside a circle of radius cep.
function rules.aim_error(cep, angle_roll, radius_roll)
  local angle = angle_roll * math.pi * 2
  local radius = cep * math.sqrt(radius_roll)
  return {x = math.cos(angle) * radius, y = math.sin(angle) * radius}
end

-- Damage rings of a ballistic warhead, scaled by class.
function rules.warhead_rings(class)
  local stats = rules.class_stats(class)
  local r = stats.radius
  local d = stats.damage
  return {
    {radius = 5 * r, explosion = 1800 * d, physical = 400 * d},
    {radius = 14 * r, explosion = 700 * d},
    {radius = 24 * r, explosion = 300 * d},
    {radius = 32 * r, explosion = 140 * d}
  }
end

function rules.intercept_probability(accuracy, factor)
  return clamp((accuracy or rules.INTERCEPT_ACCURACY) * (factor or 1), 0, 1)
end

function rules.battery_ready(distance, tick, next_shot_tick, energy, ammunition, range)
  return distance <= (range or rules.ABM_RANGE) and tick >= (next_shot_tick or 0)
    and energy >= rules.ABM_ENERGY and ammunition > 0
end

-- Returns the ready canister count and the tick of the next reload step.
function rules.reload_magazine(rounds, reload_tick, tick)
  rounds = rounds or rules.ABM_MAGAZINE
  if rounds >= rules.ABM_MAGAZINE then
    return rules.ABM_MAGAZINE, nil
  end
  reload_tick = reload_tick or (tick + rules.ABM_RELOAD_TICKS)
  while rounds < rules.ABM_MAGAZINE and tick >= reload_tick do
    rounds = rounds + 1
    reload_tick = reload_tick + rules.ABM_RELOAD_TICKS
  end
  if rounds >= rules.ABM_MAGAZINE then
    return rules.ABM_MAGAZINE, nil
  end
  return rounds, reload_tick
end

return rules
