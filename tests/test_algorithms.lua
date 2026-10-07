local root = (... and ... ~= "" and ...) or "."
package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path
}, ";")

local random = require("scripts.lib.random")
local balance = require("scripts.balance")
local targeting = require("scripts.targeting")

local tests_run = 0

local function assert_equal(actual, expected, label)
  tests_run = tests_run + 1
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_close(actual, expected, epsilon, label)
  tests_run = tests_run + 1
  if math.abs(actual - expected) > epsilon then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual), 2)
  end
end

local function assert_between(actual, minimum, maximum, label)
  tests_run = tests_run + 1
  if actual < minimum or actual > maximum then
    error(string.format("%s: expected value in [%s, %s], got %s", label, minimum, maximum, actual), 2)
  end
end

do
  local a = random.new(123456)
  local b = random.new(123456)
  for index = 1, 20 do
    assert_equal(a:next_u32(), b:next_u32(), "PRNG reproducibility " .. index)
  end

  local r = random.new(7)
  for index = 1, 100 do
    assert_between(r:range_int(3, 7), 3, 7, "PRNG integer range " .. index)
  end
end

assert_equal(balance.raid_size(0.05, 1, 1), 2, "early raid minimum")
assert_equal(balance.raid_size(1, 1, 1), 6, "late raid baseline")
assert_equal(balance.raid_size(1, 1, 1.15), 7, "scouted late raid")
assert_equal(balance.raid_size(1, 4, 2), 12, "raid hard cap")
assert_equal(balance.raid_size(0.5, 0.25, 1), 2, "raid lower cap")

assert_close(balance.intercept_probability(0, 0, 0), 0.30, 0.000001, "weak interception")
assert_close(balance.intercept_probability(1, 1, 0), 0.75, 0.000001, "best basic interception")
assert_close(balance.intercept_probability(0, 0, 1), 0.25, 0.000001, "fast missile lower clamp")
assert_close(balance.combined_intercept_probability({0.5, 0.5}), 0.75, 0.000001, "combined interception")

assert_equal(targeting.base_weight("rocket-silo", "rocket-silo"), 100, "rocket silo target weight")
assert_equal(targeting.base_weight("reactor", "nuclear-reactor"), 80, "reactor target weight")
assert_equal(targeting.base_weight("assembling-machine", "assembling-machine-3"), 25, "assembler target weight")
assert_equal(targeting.base_weight("transport-belt", "express-transport-belt"), 0, "belt exclusion")
assert_close(targeting.score(25, true, 1), 56.25, 0.000001, "active polluted target score")

io.write(string.format("PASS: %d algorithm assertions\n", tests_run))
