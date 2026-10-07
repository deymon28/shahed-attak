-- Side panel for ABM batteries, ABM wagons and AA wagons: target mode
-- (ABM launchers) plus live readiness, ammunition and magazine status.
local defense = require("scripts.defense")
local rules = require("scripts.lib.air_rules")

local battery_gui = {}
local FRAME = "shahed-attack-battery-mode"
local SELECTOR = "shahed-attack-battery-mode-selection"
local STATUS = "shahed-attack-battery-status"
local AMMO = "shahed-attack-battery-ammo"
local MODES = {"ballistic", "both", "drones"}

local ANCHORS = {
  ["shahed-attack-abm-battery"] = defines.relative_gui_type.turret_gui,
  ["shahed-attack-abm-wagon"] = defines.relative_gui_type.cargo_wagon_gui,
  ["shahed-attack-aa-wagon"] = defines.relative_gui_type.cargo_wagon_gui
}

local function opened_launcher(player)
  if not player or player.opened_gui_type ~= defines.gui_type.entity then return nil end
  local entity = player.opened
  if entity and entity.valid and ANCHORS[entity.name] then return entity end
end

local function mode_index(launcher)
  local mode = defense.get_mode(launcher)
  for index, name in ipairs(MODES) do if mode == name then return index end end
  return 1
end

local function can_edit(player, launcher)
  return launcher.operable and player.force.index == launcher.force.index
end

local function status_captions(launcher)
  if launcher.name == "shahed-attack-aa-wagon" then
    local status = defense.wagon_status(launcher)
    return {"shahed-attack-status." .. status.key}, {"shahed-attack-gui.flak-rounds", status.rounds}
  end
  local status = defense.launcher_status(launcher)
  local reload = status.reload_tick and math.max(0, math.ceil((status.reload_tick - game.tick) / 60)) or 0
  return {"shahed-attack-status." .. status.key},
    {"shahed-attack-gui.interceptors", status.ammo, status.rounds, rules.ABM_MAGAZINE, reload}
end

local function refresh(frame, player, launcher)
  if frame[SELECTOR] then
    frame[SELECTOR].selected_index = mode_index(launcher)
    frame[SELECTOR].enabled = can_edit(player, launcher)
  end
  local status, ammo = status_captions(launcher)
  frame[STATUS].caption = status
  frame[AMMO].caption = ammo
end

function battery_gui.on_closed(event)
  local player = game.get_player(event.player_index)
  local frame = player and player.gui.relative[FRAME]
  if frame then frame.destroy() end
end

function battery_gui.on_opened(event)
  battery_gui.on_closed(event)
  local player = game.get_player(event.player_index)
  local launcher = opened_launcher(player)
  if not launcher then return end
  local is_aa = launcher.name == "shahed-attack-aa-wagon"
  local frame = player.gui.relative.add({
    type = "frame", name = FRAME, direction = "vertical",
    caption = is_aa and {"shahed-attack-gui.aa-status"} or {"shahed-attack-gui.target-mode"},
    anchor = {gui = ANCHORS[launcher.name], position = defines.relative_gui_position.right, name = launcher.name},
    tags = {unit_number = launcher.unit_number}
  })
  if not is_aa then
    frame.add({type = "drop-down", name = SELECTOR, selected_index = mode_index(launcher),
      items = {{"shahed-attack-gui.ballistic"}, {"shahed-attack-gui.both"}, {"shahed-attack-gui.drones"}},
      tooltip = {"shahed-attack-gui.target-mode-description"}, enabled = can_edit(player, launcher)})
  end
  frame.add({type = "label", name = STATUS})
  frame.add({type = "label", name = AMMO})
  refresh(frame, player, launcher)
end

function battery_gui.update()
  for _, player in pairs(game.players) do
    local frame = player.gui.relative[FRAME]
    if frame then
      local launcher = opened_launcher(player)
      if not launcher or frame.tags.unit_number ~= launcher.unit_number then
        frame.destroy()
      else
        refresh(frame, player, launcher)
      end
    end
  end
end

function battery_gui.on_selection_changed(event)
  local element = event.element
  if not element or not element.valid or element.name ~= SELECTOR then return end
  local player = game.get_player(event.player_index)
  local launcher = opened_launcher(player)
  local frame = player and player.gui.relative[FRAME]
  if not launcher or not frame or frame[SELECTOR] ~= element
    or frame.tags.unit_number ~= launcher.unit_number or not can_edit(player, launcher) then return end
  defense.set_mode(launcher, MODES[element.selected_index])
  battery_gui.update()
end

function battery_gui.initialize()
  for _, player in pairs(game.players) do battery_gui.on_opened({player_index = player.index}) end
end

return battery_gui
