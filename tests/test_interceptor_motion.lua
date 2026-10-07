-- Interceptor flight: gentle start, monotonic acceleration, unchanged cruise speed.
local h = require("tests.lib.harness")
h.reset()
local current = h.surface_state()
local ordnance = require("scripts.ordnance")

local missile = {id = 1, position = {x = 1000, y = 0}, force_index = 1}
current.active_missiles[1] = missile
local battery = h.entity({name = "shahed-attack-abm-battery", position = {x = 0, y = 0.8}, orientation = 0.25})
local shot = ordnance.launch_interceptor(current, battery, missile, 0, "m1")
game.tick = shot.flight_tick
ordnance.update(game.tick)
local speeds = {}
for elapsed = 1, 18 do
  game.tick = shot.flight_tick + elapsed
  local before = {x = shot.position.x, y = shot.position.y}
  ordnance.update(game.tick)
  local dx, dy = shot.position.x - before.x, shot.position.y - before.y
  speeds[elapsed] = math.sqrt(dx * dx + dy * dy)
  if elapsed > 1 then h.check(speeds[elapsed] >= speeds[elapsed - 1] - 0.00001, "missile accelerates monotonically") end
end
h.check(speeds[1] < 0.8, "initial motion is gentle")
h.check(speeds[8] < 3.2, "the first eight ticks keep a visibly slower launch phase")
h.close(speeds[18], 6, 0.00001, "cruise speed")

-- Wagon launchers have no canister animation and fly from the mount.
local wagon = h.entity({name = "shahed-attack-abm-wagon", position = {x = 5, y = 5}})
local mobile = ordnance.launch_interceptor(current, wagon, missile, 1, "m1")
h.check(mobile.flight_tick == nil and mobile.render.visible and mobile.launch_render == nil, "wagon launch is immediate")
h.pass("interceptor acceleration and launch paths")
