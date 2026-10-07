-- Launcher side panel: per-entity mode selector, live status and stale-event safety.
local h = require("tests.lib.harness")
h.reset()
h.surface_state()

local function element(properties)
  local node = properties or {}
  node.valid = true
  node.style = {}
  node.add = function(spec)
    local child = element(spec)
    node[spec.name or tostring(#node + 1)] = child
    child.destroy = function() child.valid = false; node[spec.name] = nil end
    return child
  end
  return node
end

local defense = require("scripts.defense")
local function launcher(name)
  local entity = h.entity({name = name or "shahed-attack-abm-battery", operable = true, energy = 1e9,
    inventory = h.inventory({["shahed-attack-interceptor"] = 3, ["shahed-attack-flak-magazine"] = 2})})
  defense.on_entity_created(entity)
  return entity
end
local first, second = launcher(), launcher()
local players = {}
for index = 1, 3 do
  players[index] = {index = index, valid = true, force = h.player_force, opened_gui_type = 1,
    opened = index == 3 and second or first, gui = {relative = element()}}
end
game.players = players

local gui = require("scripts.battery_gui")
local frame_name = "shahed-attack-battery-mode"
local selector_name = "shahed-attack-battery-mode-selection"
local function frame(index) return players[index].gui.relative[frame_name] end
local function selector(index) return frame(index)[selector_name] end

for index = 1, 3 do gui.on_opened({player_index = index}) end
h.check(selector(1).selected_index == 1 and #selector(1).items == 3, "three modes, ballistic-only selected")
h.check(frame(1)["shahed-attack-battery-status"].caption[1] == "shahed-attack-status.ready", "status label shows readiness")
local ammo = frame(1)["shahed-attack-battery-ammo"].caption
h.check(ammo[1] == "shahed-attack-gui.interceptors" and ammo[2] == 3 and ammo[3] == 3 and ammo[4] == 4,
  "ammo label shows stock and ready canisters")
selector(1).selected_index = 2
gui.on_selection_changed({player_index = 1, element = selector(1)})
h.check(defense.get_mode(first) == "both" and defense.get_mode(second) == "ballistic", "selector affects the opened battery only")
h.check(selector(2).selected_index == 2 and selector(3).selected_index == 1, "other viewers see the latest mode")
selector(3).selected_index = 3
gui.on_selection_changed({player_index = 3, element = selector(3)})
h.check(defense.get_mode(second) == "drones", "third option selects drone-only")
local stale = selector(1)
players[1].opened = second
stale.selected_index = 1
gui.on_selection_changed({player_index = 1, element = stale})
h.check(defense.get_mode(first) == "both" and defense.get_mode(second) == "drones", "stale GUI events are ignored")
gui.on_closed({player_index = 1})
h.check(not frame(1), "closing removes the panel")
gui.on_opened({player_index = 1})
h.check(selector(1).selected_index == 3, "reopening reflects the stored mode")
players[1].force = h.force(9, "other")
selector(1).selected_index = 1
gui.on_selection_changed({player_index = 1, element = selector(1)})
h.check(defense.get_mode(second) == "drones", "another force cannot change settings")
second.valid = false
gui.update()
h.check(not frame(3), "destroyed launchers do not leave a stale panel")

-- Wagons: ABM wagon gets the selector, AA wagon gets a status panel.
local abm_wagon, aa_wagon = launcher("shahed-attack-abm-wagon"), launcher("shahed-attack-aa-wagon")
players[2].opened = abm_wagon
gui.on_opened({player_index = 2})
h.check(selector(2) and selector(2).selected_index == 2, "ABM wagon panel defaults to both target types")
h.check(frame(2).anchor.gui == defines.relative_gui_type.cargo_wagon_gui, "wagon panel anchors to the wagon window")
players[2].opened = aa_wagon
gui.on_opened({player_index = 2})
h.check(not selector(2), "AA wagon panel has no ABM selector")
local rounds = frame(2)["shahed-attack-battery-ammo"].caption
h.check(rounds[1] == "shahed-attack-gui.flak-rounds" and rounds[2] == 20, "AA wagon shows flak rounds")

h.pass("launcher panels: modes, status, viewers, stale events, wagons")
