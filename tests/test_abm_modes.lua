-- Per-launcher target modes for ABM batteries and ABM wagons.
local h = require("tests.lib.harness")

local current, defense, ordnance
local function fixture(mode, name)
  h.reset()
  current = h.surface_state()
  defense = require("scripts.defense")
  ordnance = require("scripts.ordnance")
  settings.global["shahed-attack-intercept-accuracy"] = {value = 1}
  game.tick = 0
  local launcher = h.entity({name = name or "shahed-attack-abm-battery", energy = 100000000,
    inventory = h.inventory({["shahed-attack-interceptor"] = 10})})
  defense.on_entity_created(launcher)
  if mode then defense.set_mode(launcher, mode) end
  return launcher, launcher.inventory
end
local function missile(id, x)
  local target = {id = id, force_index = 1, position = {x = x or 80, y = 0}, class = "medium"}
  current.active_missiles[id] = target
  return target
end
local function drone(id, kind, x, target_force)
  local entity = h.entity({unit_number = id, force = h.air_force, position = {x = x or 70, y = 0}})
  entity.die = function() entity.valid = false; current.active_drones[id] = nil; return true end
  current.active_drones[id] = {entity = entity, kind = kind or "strike", target_force_index = target_force or 1}
  return entity
end
local function advance(first, last)
  for tick = first, last do
    game.tick = tick
    for _, target in pairs(current.active_missiles) do defense.try_intercepts(target, current) end
    defense.update_drone_intercepts(tick)
    ordnance.update(tick)
  end
end
local function count(inventory) return inventory.get_item_count("shahed-attack-interceptor") end

local battery, inventory = fixture("drones")
local target = missile(1)
for tick = 1, 30 do game.tick = tick; defense.try_intercepts(target, current) end
h.check(count(inventory) == 10, "drone-only batteries ignore ballistic missiles")

battery, inventory = fixture()
local shahed = drone(1)
advance(1, 60)
h.check(count(inventory) == 10 and shahed.valid, "batteries default to ballistic-only")
h.check(defense.get_mode(battery) == "ballistic", "missing mode has a safe default")
target = missile(2)
advance(61, 120)
h.check(target.intercepted and count(inventory) <= 9, "default ballistic interception works")

for _, kind in ipairs({"strike", "heavy", "decoy"}) do
  battery, inventory = fixture("drones")
  shahed = drone(1, kind)
  advance(1, 60)
  h.check(not shahed.valid and count(inventory) <= 9, "drone interception destroys " .. kind .. " targets")
  h.check(battery.energy <= 90000000, "drone launches keep the energy cost")
end

battery, inventory = fixture("both")
shahed = drone(1)
target = missile(1)
advance(1, 30)
local _, shot = next(current.projectiles)
h.check(shot and shot.target_missile_id == 1 and not shot.target_drone, "mixed mode prefers ballistics")
advance(31, 160)
h.check(target.intercepted and not shahed.valid, "mixed mode resumes drone defense afterwards")

battery, inventory = fixture("drones")
shahed = drone(1)
advance(1, 24)
h.check(count(inventory) <= 9, "launch at a drone before changing mode")
local next_shot = current.battery_next_shot[battery.unit_number]
h.check(defense.set_mode(battery, "ballistic"), "mode change accepted")
h.check(current.battery_next_shot[battery.unit_number] == next_shot, "mode change keeps the cooldown")
advance(25, 65)
h.check(not shahed.valid, "launched interceptors finish after switching mode")
h.check(not defense.set_mode(battery, "invalid") and defense.get_mode(battery) == "ballistic", "invalid modes rejected")

battery, inventory = fixture("drones")
local recon = drone(1, "recon")
local distant = drone(2, "strike", 193)
local other = drone(3, "heavy", 40, 3)
advance(1, 60)
h.check(count(inventory) == 10 and recon.valid and distant.valid and other.valid,
  "recon, out-of-range and other-force targets are ignored")

battery, inventory = fixture("drones")
shahed = drone(1)
advance(1, 24)
shahed.valid = false
current.active_drones[1] = nil
advance(25, 80)
h.check(next(current.projectiles) == nil, "lost drone targets: interceptors self-destruct and clean up")

battery, inventory = fixture("drones")
settings.global["shahed-attack-intercept-accuracy"] = {value = 0}
shahed = drone(1)
advance(1, 70)
h.check(shahed.valid and current.counters.interceptor_misses >= 1, "misses consume rounds without a second roll")

-- Mobile launcher: no grid power, shorter range, defaults to both target types.
local wagon
wagon, inventory = fixture(nil, "shahed-attack-abm-wagon")
wagon.energy = 0
h.check(defense.get_mode(wagon) == "both", "ABM wagons default to ballistics and Shaheds")
shahed = drone(1, "strike", 100)
advance(1, 60)
h.check(not shahed.valid and count(inventory) <= 9, "ABM wagons fire without grid power")
wagon, inventory = fixture(nil, "shahed-attack-abm-wagon")
shahed = drone(1, "strike", 150)
advance(1, 60)
h.check(shahed.valid and count(inventory) == 10, "ABM wagon range is shorter than a battery")
h.check(#h.renders > 0, "wagon turret head is drawn")

h.pass("ABM target modes, priority, drone kinds, mode changes, target loss and ABM wagons")
