local root = (... and ... ~= "" and ...) or "."
package.path = table.concat({root .. "/?.lua", root .. "/?/init.lua", package.path}, ";")

local alert_policy = require("scripts.lib.alert_policy")
local audio_policy = require("scripts.lib.audio_policy")
local defense_math = require("scripts.lib.defense_math")
local flight_loaded, flight_math = pcall(require, "scripts.lib.flight_math")

local tests_run = 0

local function equal(actual, expected, label)
  tests_run = tests_run + 1
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

local function close(actual, expected, epsilon, label)
  tests_run = tests_run + 1
  if math.abs(actual - expected) > epsilon then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual), 2)
  end
end

equal(flight_loaded, true, "flight geometry module loads")

equal(alert_policy.normalize("both"), "both", "both mode remains unchanged")
equal(alert_policy.normalize("global-sound"), "global-sound", "global mode remains unchanged")
equal(alert_policy.normalize("circuit-only"), "circuit-only", "circuit mode remains unchanged")
equal(alert_policy.normalize("invalid"), "both", "invalid mode uses safe default")
equal(alert_policy.plays_global("both", true), true, "both plays enabled personal sound")
equal(alert_policy.plays_global("both", false), false, "personal mute wins in both mode")
equal(alert_policy.plays_global("global-sound", true), true, "global mode plays sound")
equal(alert_policy.plays_global("circuit-only", true), false, "circuit mode suppresses sound")
equal(alert_policy.publishes_circuit("both"), true, "both publishes signals")
equal(alert_policy.publishes_circuit("global-sound"), false, "global mode suppresses signals")
equal(alert_policy.publishes_circuit("circuit-only"), true, "circuit mode publishes signals")

equal(audio_policy.can_play(nil, 100, 30), true, "first positional sound can play")
equal(audio_policy.can_play(100, 129, 30), false, "sound remains blocked before cooldown expiry")
equal(audio_policy.can_play(100, 130, 30), true, "sound plays at exact cooldown expiry")
equal(audio_policy.can_play(100, 100, 0), true, "zero cooldown permits same-tick sound")

local diagonal = flight_math.normalized_motion({x = 0, y = 0}, {x = 3, y = 4}, 0)
close(diagonal.x, 0.6, 0.000001, "recorded horizontal flight vector")
close(diagonal.y, 0.8, 0.000001, "recorded vertical flight vector")

local north = flight_math.normalized_motion({x = 5, y = 5}, {x = 5, y = 5}, 0)
close(north.x, 0, 0.000001, "orientation fallback horizontal vector")
close(north.y, -1, 0.000001, "orientation fallback north vector")

local projected = flight_math.project_forward({x = 10, y = 20}, {x = 1, y = 0}, 8, 0)
close(projected.x, 18, 0.000001, "wreck continues forward")
close(projected.y, 20, 0.000001, "wreck has no deviation at zero angle")

equal(flight_math.direction_index({x = 0, y = -1}, 8), 0, "north wreck direction")
equal(flight_math.direction_index({x = 1, y = -1}, 8), 1, "north-east wreck direction")
equal(flight_math.direction_index({x = 1, y = 0}, 8), 2, "east wreck direction")
equal(flight_math.direction_index({x = 0, y = 1}, 8), 4, "south wreck direction")
equal(flight_math.direction_index({x = -1, y = 0}, 8), 6, "west wreck direction")
equal(flight_math.direction_index({x = -0.001, y = -1}, 8), 0, "wreck direction wraps around north")

local orbit_east = flight_math.orbit_point({x = 10, y = 10}, 20, 12, 0)
close(orbit_east.x, 30, 0.000001, "recon orbit east point")
close(orbit_east.y, 10, 0.000001, "recon orbit east height")
local orbit_south = flight_math.orbit_point({x = 10, y = 10}, 20, 12, math.pi / 2)
close(orbit_south.x, 10, 0.000001, "recon orbit south width")
close(orbit_south.y, 22, 0.000001, "recon orbit south point")

local interpolation_cases = {
  {-20, 0, 0},
  {0, 0, 0},
  {25, 0.25, 25},
  {50, 0.5, 50},
  {75, 0.75, 75},
  {100, 1, 100},
  {140, 1, 100}
}
for index, case in ipairs(interpolation_cases) do
  local point, progress = flight_math.lerp_clamped({x = 0, y = 10}, {x = 100, y = 30}, case[1], 100)
  close(progress, case[2], 0.000001, "clamped interpolation progress " .. index)
  close(point.x, case[3], 0.000001, "clamped interpolation position " .. index)
end


io.write(string.format("PASS: %d runtime-rule assertions\n", tests_run))
