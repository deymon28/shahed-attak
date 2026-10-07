-- Raid planning: real sources only, groups, staggering, bearings, decoys,
-- suppression targets, weaker warheads, trains and the AA wagon.
local h = require("tests.lib.harness")
h.reset()
local current = h.surface_state()

h.entity_factory = function(surface, args)
  if not args.name:find("drone", 1, true) then return {valid = true} end
  local unit = h.entity({name = args.name, position = {x = args.position.x, y = args.position.y},
    surface = surface, force = h.air_force, speed = 0.08})
  unit.commandable = {set_command = function(command) unit.command = command end}
  return unit
end

local raids = require("scripts.raids")
local director = require("scripts.director")
local defense = require("scripts.defense")
local ordnance = require("scripts.ordnance")
local random = require("scripts.lib.random")

local factory = h.entity({type = "assembling-machine", name = "assembling-machine-2", position = {x = 0, y = 0}})
for i = 1, 10 do
  h.entity({type = "furnace", name = "stone-furnace", position = {x = i * 3, y = 5}})
end

-- No airfield, no raid: attacks never spawn from empty space.
local event_id, reason = raids.spawn_event(h.nauvis, h.player_force, factory, "raid", 6, {})
h.check(event_id == nil and reason == "no-source", "raids need a real airfield")

local airfield = h.entity({name = "shahed-attack-airfield", position = {x = -600, y = 0}, force = h.air_force})
require("scripts.infrastructure").initialize()

local function drones()
  local list = {}
  for _, record in pairs(current.active_drones) do list[#list + 1] = record end
  return list
end
local function pending_groups()
  local count = 0
  for _, pending in pairs(current.pending_events) do
    if pending.kind == "drone-group" then count = count + 1 end
  end
  return count
end

event_id = raids.spawn_event(h.nauvis, h.player_force, factory, "raid", 6, {generator = random.new(5)})
h.check(event_id and #drones() == 6 and pending_groups() == 0, "small raid launches as one group")
for _, record in ipairs(drones()) do
  h.check(record.source == airfield and record.origin.x == -600, "every drone starts at the airfield")
end

-- Mass raid: groups of eight, the first now, the rest queued with bearings.
raids.clear(current)
h.check(next(current.active_drones) == nil, "clear removes drones")
event_id = raids.spawn_event(h.nauvis, h.player_force, factory, "raid", 30, {generator = random.new(9)})
h.check(event_id and #drones() == 8, "first group of a mass raid launches immediately")
h.check(pending_groups() == 3, "remaining groups are queued")
local swung = 0
for _, pending in pairs(current.pending_events) do
  h.check(pending.tick > game.tick and pending.group.event_size == 30, "queued groups launch later")
  if pending.group.bearing ~= 0 then swung = swung + 1 end
end
h.check(swung == 3, "later groups approach on other bearings")
game.tick = 60 * 60 * 5
director.process_pending(game.tick)
h.check(#drones() == 30 and pending_groups() == 0, "queued groups launch from the airfield")
local with_via = 0
for _, record in ipairs(drones()) do
  if record.via then with_via = with_via + 1 end
end
h.check(with_via >= 22, "swinging groups fly through an outer waypoint")

-- The active-drone limit caps mass raids.
raids.clear(current)
settings.global["shahed-attack-max-active-drones"] = {value = 20}
raids.spawn_event(h.nauvis, h.player_force, factory, "raid", 40, {generator = random.new(3), stagger = false})
h.check(#drones() == 20, "never more drones than the configured limit")
settings.global["shahed-attack-max-active-drones"] = nil
raids.clear(current)

-- Late evolution: decoys and air-defense suppression appear.
h.evolution = 1
local aa = h.entity({name = "shahed-attack-aa-turret", position = {x = 20, y = 20}})
defense.on_entity_created(aa)
raids.spawn_event(h.nauvis, h.player_force, factory, "raid", 40, {generator = random.new(11), stagger = false})
local decoys, suppression = 0, 0
for _, record in ipairs(drones()) do
  if record.kind == "decoy" then decoys = decoys + 1 end
  if record.role == "suppression" then
    suppression = suppression + 1
    h.check(record.target_entity == aa, "suppression aircraft target the AA gun")
  end
end
h.check(decoys > 0 and suppression > 0, "late raids carry decoys and suppression aircraft")
h.check(current.counters.decoys_launched == decoys, "decoys counted")
settings.global["shahed-attack-decoys-enabled"] = {value = false}
settings.global["shahed-attack-defense-suppression-enabled"] = {value = false}
raids.clear(current)
raids.spawn_event(h.nauvis, h.player_force, factory, "raid", 40, {generator = random.new(11), stagger = false})
for _, record in ipairs(drones()) do
  h.check(record.kind ~= "decoy" and record.role ~= "suppression", "disabled toggles are respected")
end
raids.clear(current)

-- Weaker strike warhead; decoys barely scratch.
local victim = h.entity({type = "assembling-machine", name = "assembling-machine-1", position = {x = 100, y = 100}, health = 1000})
local function detonate(kind)
  victim.damage_taken = 0
  local unit = h.entity({name = "shahed-attack-" .. kind .. "-drone", position = {x = 100, y = 100}, force = h.air_force})
  local record = {entity = unit, kind = kind, event_id = 1, target_force_index = 1}
  current.active_drones[unit.unit_number] = record
  raids.detonate(record, kind == "heavy")
  return victim.damage_taken
end
local strike_damage = detonate("strike"); h.check(strike_damage == 140, "strike warhead reduced to 140, got " .. tostring(strike_damage))
h.check(detonate("heavy") == 320, "heavy warhead reduced to 320")
h.check(detonate("decoy") == 10, "decoys carry no real warhead")

-- Trains: drones follow a moving target and attack it directly when close.
h.evolution = 0
local locomotive = h.entity({type = "locomotive", name = "locomotive", position = {x = 50, y = 0},
  train = {speed = 0.5}})
raids.spawn_event(h.nauvis, h.player_force, locomotive, "raid", 2, {generator = random.new(4), stagger = false})
local record = drones()[1]
record.entity.position = {x = 40, y = 0}
locomotive.position = {x = 55, y = 0}
game.tick = game.tick + 60
raids.update(game.tick)
h.check(record.target_position.x == 55, "drones track the train position")
h.check(record.attack_target == locomotive and record.entity.command.type == defines.command.attack,
  "close drones switch to a direct attack on the train")
raids.clear(current)

-- AA wagon: script-aimed flak with magazines from cargo.
local wagon = h.entity({name = "shahed-attack-aa-wagon", position = {x = 0, y = 0},
  inventory = h.inventory({["shahed-attack-flak-magazine"] = 1})})
defense.on_entity_created(wagon)
local target = h.entity({name = "shahed-attack-strike-drone", position = {x = 0, y = -20}, force = h.air_force, speed = 0.08})
current.active_drones[target.unit_number] = {entity = target, kind = "strike", target_force_index = 1}
for tick = game.tick + 1, game.tick + 400 do
  game.tick = tick
  defense.update_drone_intercepts(tick)
  ordnance.update(tick)
end
h.check(current.counters.flak_shots >= 10, "AA wagon fires at drones in range")
h.check(wagon.inventory.get_item_count("shahed-attack-flak-magazine") == 0, "flak magazines are consumed")
h.check(defense.wagon_status(wagon).rounds < 10, "rounds counted down")
local frame = current.wagon_state[wagon.unit_number].head.animation_offset
h.check(frame == 0, "turret head points north at the target")

h.pass("raid planning, mass raids, decoys, suppression, warheads, trains and AA wagons")
