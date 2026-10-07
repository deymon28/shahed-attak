-- ABM fire control: smooth acquisition, fire doctrine, magazines, range and costs.
local h = require("tests.lib.harness")
h.reset()
local current = h.surface_state()
local defense = require("scripts.defense")
local ordnance = require("scripts.ordnance")
local rules = require("scripts.lib.air_rules")

local batteries = {}
for i = 1, 5 do
  local battery = h.entity({name = "shahed-attack-abm-battery", position = {x = 0, y = 0},
    energy = 100000000, inventory = h.inventory({["shahed-attack-interceptor"] = 10})})
  defense.on_entity_created(battery)
  batteries[i] = battery
end
local function stock(battery) return battery.inventory.get_item_count("shahed-attack-interceptor") end
local function total_stock()
  local sum = 0
  for _, battery in ipairs(batteries) do sum = sum + stock(battery) end
  return sum
end
local function launches() return 50 - total_stock() end

local missile = {id = 1, force_index = 1, position = {x = 100, y = 0}, class = "medium"}
current.active_missiles[1] = missile
h.check(not defense.try_intercepts(missile, current) and launches() == 0, "batteries aim before firing")

local previous, first_launch = 0, nil
for tick = 1, 40 do
  game.tick = tick
  defense.try_intercepts(missile, current)
  local heading = batteries[1].orientation
  h.check(heading >= previous and heading - previous <= rules.ABM_TURN_RATE + 1e-6, "turret turns smoothly")
  previous = heading
  if launches() > 0 then first_launch = tick break end
end
h.check(first_launch and first_launch >= 15 and first_launch <= 30, "quarter-turn acquisition stays bounded")
h.check(launches() == 2, "fire doctrine: only two interceptors fly at one target")
h.check(ordnance.engaged(current, "m1") == 2, "engagements are counted")
for _, battery in ipairs(batteries) do
  h.check(battery.energy == 100000000 or battery.energy == 90000000, "energy charged only for launches")
end

-- A miss frees a slot: shoot-look-shoot.
for _, shot in pairs(current.projectiles) do
  shot.accuracy = 0
end
for tick = first_launch + 1, first_launch + 60 do
  game.tick = tick
  defense.try_intercepts(missile, current)
  ordnance.update(tick)
end
h.check(launches() > 2, "launchers fire again after interceptors miss")
h.check(ordnance.engaged(current, "m1") <= 2, "never more than the doctrine limit in flight")

-- Destroyed targets stop new launches and orphaned rounds self-destruct.
missile.intercepted = true
local before = launches()
for tick = game.tick + 1, game.tick + 40 do
  game.tick = tick
  h.check(defense.try_intercepts(missile, current), "destroyed missile reports done")
  ordnance.update(tick)
end
h.check(launches() == before, "no launch at a destroyed missile")
h.check(next(current.projectiles) == nil, "orphaned interceptors self-destruct and clean up")
h.check(ordnance.engaged(current, "m1") == 0, "engagement counter released")

-- Magazine: four ready canisters, then one every ten seconds.
h.reset()
current = h.surface_state()
defense = require("scripts.defense")
ordnance = require("scripts.ordnance")
settings.global["shahed-attack-interceptors-per-target"] = {value = 8}
local battery = h.entity({name = "shahed-attack-abm-battery", energy = 1e9,
  inventory = h.inventory({["shahed-attack-interceptor"] = 20})})
defense.on_entity_created(battery)
local target = {id = 7, force_index = 1, position = {x = 0, y = -100}, class = "heavy"}
current.active_missiles[7] = target
for tick = 1, 400 do
  game.tick = tick
  defense.try_intercepts(target, current)
end
h.check(20 - stock(battery) == 4, "a launcher fires its four ready canisters, then waits")
h.check(defense.launcher_status(battery).key == "reloading", "status shows reloading")
for tick = 401, 1400 do
  game.tick = tick
  defense.try_intercepts(target, current)
end
h.check(20 - stock(battery) == 5 or 20 - stock(battery) == 6, "reloaded canisters fire one per ten seconds")
for _, shot in pairs(current.projectiles) do
  h.check(shot.accuracy < 0.7, "heavy missiles are harder to hit than the base accuracy")
  break
end

-- Range limit and resource gates.
target.position = {x = 0, y = -(rules.ABM_RANGE + 1)}
local stock_before = stock(battery)
for tick = 5000, 5100 do game.tick = tick; defense.try_intercepts(target, current) end
h.check(stock(battery) == stock_before, "no launch outside the finite radius")
target.position = {x = 0, y = -50}
battery.energy = 0
for tick = 5101, 5200 do game.tick = tick; defense.try_intercepts(target, current) end
h.check(stock(battery) == stock_before, "fixed batteries need 10 MJ")

h.pass("ABM acquisition, fire doctrine, shoot-look-shoot, magazines, range and costs")
