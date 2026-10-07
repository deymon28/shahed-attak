-- Shot-down drones fall as wrecks of their own airframe family.
local h = require("tests.lib.harness")
h.reset()
local current = h.surface_state()
local raids = require("scripts.raids")

local drone = h.entity({unit_number = 1, position = {x = 10, y = 0}, orientation = 0.25, force = h.air_force})
current.active_drones[1] = {kind = "recon", last_motion = {x = 1, y = 0}}
raids.on_entity_died({entity = drone})
local created = h.nauvis.created[#h.nauvis.created]
h.check(created and created.name:find("falling-recon-wreck", 1, true), "recon falls with its own airframe")
h.check(current.active_drones[1] == nil and current.counters.drones_destroyed == 1, "death removes and counts the drone once")
current.active_drones[1] = {kind = "decoy", last_motion = {x = 1, y = 0}}
raids.on_entity_died({entity = drone})
created = h.nauvis.created[#h.nauvis.created]
h.check(created.name:find("falling-wreck-", 1, true) and not created.name:find("recon", 1, true),
  "decoys fall as strike-drone wrecks")
h.pass("wreck families")
