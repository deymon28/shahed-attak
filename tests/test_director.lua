-- Natural attack scheduling: grace period, ballistic gates and toggles,
-- salvo growth, missile classes and staggered salvo launches.
local h = require("tests.lib.harness")
h.reset()
local current = h.surface_state()
h.entity_factory = function(surface, args)
  if args.name == "shahed-attack-ballistic-sound-source" then
    return h.entity({name = args.name, surface = surface, teleport = function() end})
  end
  if args.name:find("drone", 1, true) then
    local unit = h.entity({name = args.name, position = args.position, surface = surface, force = h.air_force, speed = 0.08})
    unit.commandable = {set_command = function(command) unit.command = command end}
    return unit
  end
  return {valid = true}
end

local director = require("scripts.director")
local targeting = require("scripts.targeting")
local infrastructure = require("scripts.infrastructure")
local DAY = h.nauvis.ticks_per_day

for i = 1, 20 do
  targeting.register(h.entity({type = "assembling-machine", name = "assembling-machine-1", position = {x = i * 4, y = 0}}))
end
h.entity({name = "shahed-attack-airfield", position = {x = -700, y = 0}, force = h.air_force})
h.entity({name = "shahed-attack-ballistic-site", position = {x = 1500, y = 0}, force = h.air_force})
infrastructure.initialize()
director.initialize()

local function missiles()
  local count = 0
  for _ in pairs(current.active_missiles) do count = count + 1 end
  return count
end
local function queued(kind)
  local count = 0
  for _, pending in pairs(current.pending_events) do
    if pending.kind == kind then count = count + 1 end
  end
  return count
end
local function count_drones()
  local count = 0
  for _ in pairs(current.active_drones) do count = count + 1 end
  return count
end

-- Grace period: no raid before two days.
h.evolution = 0.1
game.tick = DAY
director.update(game.tick)
h.check(count_drones() == 0, "no raids during the grace period")
game.tick = 2 * DAY + 600
current.next_raid_tick = 0
director.update(game.tick)
h.check(count_drones() > 0 or current.counters.recon > 0, "first raid after the grace period")
h.check(current.next_raid_tick > game.tick, "next raid scheduled")

-- Ballistic gates: calendar, evolution, chemistry, preparation.
local ok, reason = director.ballistic_available(h.nauvis, current, h.player_force, 5 * DAY)
h.check(not ok and reason == "calendar", "too early in the game")
h.evolution = 0.3
ok, reason = director.ballistic_available(h.nauvis, current, h.player_force, 13 * DAY)
h.check(not ok and reason == "chemistry", "waits for chemical science")
h.player_force.technologies["chemical-science-pack"] = {researched = true}
game.tick = 13 * DAY
director.update(game.tick)
h.check(current.ballistic_readiness[1] == game.tick, "chemistry tick recorded")
ok, reason = director.ballistic_available(h.nauvis, current, h.player_force, game.tick + 60)
h.check(not ok and reason == "preparation", "preparation window after chemistry")
ok = director.ballistic_available(h.nauvis, current, h.player_force, game.tick + 30 * 3600)
h.check(ok, "ballistics available after the preparation window")

-- The disabled toggle really disables natural ballistics.
settings.global["shahed-attack-ballistic-enabled"] = {value = false}
game.tick = 13 * DAY + 31 * 3600
current.next_ballistic_tick = 0
director.update(game.tick)
h.check(missiles() == 0 and queued("ballistic") == 0, "disabled ballistics never launch")
settings.global["shahed-attack-ballistic-enabled"] = nil

-- Early salvos: a single light, inaccurate missile.
current.next_ballistic_tick = 0
current.next_raid_tick = math.huge
game.tick = game.tick + 600
director.update(game.tick)
h.check(missiles() == 1 and queued("ballistic") == 0, "first ballistic strike is a single missile")
local _, first = next(current.active_missiles)
h.check(first.class == "light", "early missiles are light")
h.check(current.next_ballistic_tick > game.tick, "next ballistic attempt scheduled")

-- Late salvos: several heavy missiles, launched a few seconds apart.
for id in pairs(current.active_missiles) do current.active_missiles[id] = nil end
h.evolution = 1
current.next_ballistic_tick = 0
game.tick = game.tick + 600
director.update(game.tick)
local salvo = missiles() + queued("ballistic")
h.check(salvo >= 4, "late salvos contain several missiles (got " .. salvo .. ")")
local _, late = next(current.active_missiles)
h.check(late.class == "heavy", "late missiles are heavy")
game.tick = game.tick + 30 * 60
director.process_pending(game.tick)
h.check(missiles() == salvo and queued("ballistic") == 0, "queued salvo missiles launch")

-- Recon toggle: natural raids never send reconnaissance when disabled.
settings.global["shahed-attack-recon-enabled"] = {value = false}
require("scripts.raids").clear(current)
for _ = 1, 20 do
  current.next_raid_tick = 0
  current.next_ballistic_tick = math.huge
  game.tick = game.tick + 600
  director.update(game.tick)
end
h.check(count_drones() > 0, "raids launched while recon disabled")
for _, record in pairs(current.active_drones) do
  h.check(record.kind ~= "recon", "recon disabled: no reconnaissance drones")
end

-- Admin cleanup removes queued salvo missiles as well as flying ones.
local ballistics = require("scripts.ballistics")
local site = h.nauvis.find_entities_filtered({name = "shahed-attack-ballistic-site"})[1]
local site_target = h.nauvis.find_entities_filtered({type = "assembling-machine"})[1]
ballistics.clear(current)
director.launch_salvo(h.nauvis, current, h.player_force, site_target, require("scripts.lib.random").new(9), 3, site)
h.check(queued("ballistic") == 2, "scripted salvo queues the rest of the missiles")
local salvo_ids = {}
for _, missile in pairs(current.active_missiles) do salvo_ids[missile.salvo_id or "none"] = true end
for _, pending in pairs(current.pending_events) do
  if pending.kind == "ballistic" then salvo_ids[pending.salvo_id or "none"] = true end
end
h.check(not salvo_ids.none, "scripted salvo missiles share a salvo id")
ballistics.clear(current)
h.check(missiles() == 0 and queued("ballistic") == 0, "clear removes queued salvo missiles")

-- Peaceful mode switched on during the game stops natural attacks.
require("scripts.raids").clear(current)
h.nauvis.peaceful_mode = true
current.next_raid_tick = 0
current.next_ballistic_tick = 0
game.tick = game.tick + 600
director.update(game.tick)
h.check(count_drones() == 0 and missiles() == 0 and queued("ballistic") == 0, "no natural attacks in peaceful mode")
h.nauvis.peaceful_mode = false

-- A grace period shorter than two days is honoured on a new world.
h.reset()
settings.global["shahed-attack-grace-period-days"] = {value = 0.5}
current = h.surface_state()
director = require("scripts.director")
director.initialize()
h.check(current.next_raid_tick == math.floor(0.5 * DAY), "first raid scheduled at the end of a short grace period")
settings.global["shahed-attack-grace-period-days"] = {value = 5}
h.reset()
settings.global["shahed-attack-grace-period-days"] = {value = 5}
current = h.surface_state()
require("scripts.director").initialize()
h.check(current.next_raid_tick == 5 * DAY, "long grace period delays the first raid")

h.pass("grace period, ballistic gates, toggles, salvo growth and staggered launches")
