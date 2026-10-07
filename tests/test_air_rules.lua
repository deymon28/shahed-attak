package.path = './?.lua;' .. package.path
local rules = require('scripts.lib.air_rules')
local random = require('scripts.lib.random')
local n = 0
local function check(value, message) n = n + 1; assert(value, message) end
local target = {x = 0, y = 0}
for _, item in ipairs({{'north',0,-100},{'north-east',100,-100},{'east',100,0},
  {'south-east',100,100},{'south',0,100},{'south-west',-100,100},{'west',-100,0},{'north-west',-100,-100}}) do
  check(rules.incoming_direction({x=item[2],y=item[3]}, target) == item[1], 'incoming ' .. item[1])
end
check(rules.drone_warning(288, 0.08, true), 'one minute warning')
check(not rules.drone_warning(1000, 0.08, true), 'distant launch stays quiet')
check(not rules.drone_warning(250, 0.08, false), 'radar required for early warning')
check(rules.drone_warning(49, 0.08, false), 'late fallback')
check(rules.ballistic_duration(1000) >= 45 * 60, 'minimum reaction interval')
check(rules.ballistic_duration(10000) > rules.ballistic_duration(1000), 'distance affects travel')
local previous, first_step, last_step = 0
for tick = 1, 2700 do
  local progress = rules.ballistic_progress(tick, 2700)
  check(progress >= previous and progress <= 1, 'monotonic progress')
  if tick == 1 then first_step = progress end
  last_step, previous = progress - previous, progress
end
check(last_step > first_step * 10, 'missile accelerates')
check(previous == 1, 'reaches exact impact')
check(rules.battery_ready(192, 60, 60, 10000000, 1), 'inclusive range and cooldown')
check(not rules.battery_ready(192.1, 60, 60, 10000000, 1), 'outside range')
check(not rules.battery_ready(20, 59, 60, 10000000, 1), 'cooldown active')
check(rules.battery_ready(1, 120, 120, 10000000, 1), 'close-range repeated launch')
check(not rules.battery_ready(20, 60, 60, 9999999, 1), 'insufficient energy')
check(not rules.battery_ready(20, 60, 60, 10000000, 0), 'empty magazine')
local rng, hits = random.new(137), 0
for _ = 1, 10000 do if rng:next_float() < rules.INTERCEPT_ACCURACY then hits = hits + 1 end end
check(hits > 6800 and hits < 7200, 'independent 70 percent distribution')
print(string.format('PASS: %d air-war rule assertions; %d/10000 intercepts', n, hits))
