local random = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local generator = {}
generator.__index = generator

function random.normalize_seed(seed)
  local normalized = math.floor(math.abs(tonumber(seed) or 1)) % MODULUS
  if normalized == 0 then
    normalized = 1
  end
  return normalized
end

function random.step(state)
  return (random.normalize_seed(state) * MULTIPLIER) % MODULUS
end

function random.new(seed)
  return setmetatable({state = random.normalize_seed(seed)}, generator)
end

function generator:next_u32()
  self.state = random.step(self.state)
  return self.state
end

function generator:next_float()
  return self:next_u32() / MODULUS
end

function generator:range_int(minimum, maximum)
  if maximum < minimum then
    minimum, maximum = maximum, minimum
  end
  return minimum + math.floor(self:next_float() * (maximum - minimum + 1))
end

function generator:range_float(minimum, maximum)
  return minimum + self:next_float() * (maximum - minimum)
end

return random
