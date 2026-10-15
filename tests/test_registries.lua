-- Target registry compaction, source registry, Nauvis scope and surface cleanup.
local h = require("tests.lib.harness")
h.reset()
local current, state = h.surface_state()
local targeting = require("scripts.targeting")
local infrastructure = require("scripts.infrastructure")

-- Targets: destroyed entries are swapped out, so storage does not grow.
local entities = {}
for i = 1, 6 do
  entities[i] = h.entity({type = "assembling-machine", name = "assembling-machine-1", position = {x = i, y = 0}})
  h.check(targeting.register(entities[i]), "target registered")
end
h.check(not targeting.register(entities[1]), "duplicate registration ignored")
h.check(targeting.count(1, 1) == 6, "six targets")
local registrations = {}
for registration, record in pairs(state.root().target_registrations) do registrations[record.unit_number] = registration end
targeting.on_object_destroyed({registration_number = registrations[entities[2].unit_number]})
targeting.on_object_destroyed({registration_number = registrations[entities[6].unit_number]})
h.check(targeting.count(1, 1) == 4, "destroyed targets leave the list")
local list = state.root().targets[1][1]
for index, entity in ipairs(list.entities) do
  h.check(entity.valid and list.by_unit[entity.unit_number] == index and list.units[index] == entity.unit_number,
    "compact list keeps indexes consistent")
end
h.check(#list.entities == 4 and list.entities[5] == nil, "no holes remain")
-- Rebuilding the same building adds exactly one live entry.
local rebuilt = h.entity({type = "assembling-machine", name = "assembling-machine-1"})
targeting.register(rebuilt)
h.check(targeting.count(1, 1) == 5, "rebuilt entity adds one entry")

-- Legacy schema-5 lists with `false` holes are compacted on initialize.
state.root().targets[1][1] = {entries = {entities[1], false, entities[3], false}, by_unit = {}}
targeting.initialize()
h.check(targeting.count(1, 1) == 2, "legacy lists compacted")

-- Trains are targets; enemy-owned and off-Nauvis entities are not.
local locomotive = h.entity({type = "locomotive", name = "locomotive"})
h.check(targeting.is_target(locomotive) and targeting.is_rolling_stock(locomotive), "locomotives are targets")
local hostile = h.entity({type = "furnace", name = "stone-furnace", force = h.enemy_force})
h.check(not targeting.is_target(hostile), "enemy buildings are not targets")
local other_surface = h.surface(2, "platform-1")
game.surfaces[2] = other_surface
local offworld = h.entity({type = "assembling-machine", name = "assembling-machine-1", surface = other_surface})
h.check(not targeting.is_target(offworld), "only Nauvis is attacked")
h.check(state.ensure_surface(other_surface) == nil, "no state for unsupported surfaces")

-- Sources: keyed by unit number, removed on destruction, sorted by distance.
local near = h.entity({name = "shahed-attack-airfield", position = {x = 500, y = 0}, force = h.air_force})
local far = h.entity({name = "shahed-attack-airfield", position = {x = 3000, y = 0}, force = h.air_force})
local beyond = h.entity({name = "shahed-attack-airfield", position = {x = 5000, y = 0}, force = h.air_force})
infrastructure.initialize()
local in_range = infrastructure.sources_in_range(current, "airfields", {x = 0, y = 0})
h.check(#in_range == 2 and in_range[1] == near and in_range[2] == far, "nearest airfield first, out of range excluded")
h.check(infrastructure.source_near(current, "airfields", {x = 3005, y = 0}, 16) == far, "source lookup by position")
for registration, record in pairs(state.root().source_registrations) do
  if record.unit_number == near.unit_number then
    infrastructure.on_object_destroyed({registration_number = registration})
  end
end
h.check(current.sources.airfields[near.unit_number] == nil and infrastructure.count(current, "airfields") == 2,
  "destroyed source unregistered")
h.check(beyond.valid, "sources beyond range stay registered")

-- Merged forces: the absorbed force's buildings are rescanned for the
-- destination force and its planning state carries over.
local blue = h.force(4, "blue")
game.forces.blue, game.forces[4] = blue, blue
local blue_building = h.entity({type = "lab", name = "lab", force = blue})
targeting.register(blue_building)
current.intelligence[4] = 2
current.ballistic_readiness[4] = 100
current.active_missiles[99] = {id = 99, force_index = 4}
h.check(targeting.count(1, 4) == 1, "second force registered")
blue_building.force = h.player_force
game.forces.blue, game.forces[4] = nil, nil
state.merge_forces(4, 1)
targeting.on_forces_merged(4)
h.check(targeting.count(1, 4) == 0, "absorbed force list dropped")
for _, record in pairs(state.root().target_registrations) do
  h.check(record.force_index ~= 4, "absorbed force registrations dropped")
end
h.check(state.root().scan_queue[1] ~= nil, "surface rescan queued")
targeting.register(blue_building)
h.check(state.root().targets[1][1].by_unit[blue_building.unit_number] ~= nil, "building listed for the destination force")
h.check(current.intelligence[1] == 2 and current.intelligence[4] == nil, "intelligence carried over")
h.check(current.ballistic_readiness[1] == 100 and current.ballistic_readiness[4] == nil, "readiness carried over")
h.check(current.active_missiles[99].force_index == 1, "missiles retargeted to the destination force")
current.active_missiles[99] = nil

-- Deleting a surface forgets everything that belonged to it.
state.root().scan_queue[1] = {chunks = {}, cursor = 1}
state.root().audio_cooldowns[1] = {x = 1}
state.forget_surface(1)
local root = state.root()
h.check(root.surfaces[1] == nil and root.targets[1] == nil and root.scan_queue[1] == nil
  and root.audio_cooldowns[1] == nil, "surface tables cleared")
for _, map_name in ipairs({"target_registrations", "source_registrations", "defense_registrations"}) do
  for _, record in pairs(root[map_name]) do
    h.check(record.surface_index ~= 1, map_name .. " cleared")
  end
end

h.pass("target compaction, trains, Nauvis scope, source registry and surface cleanup")
