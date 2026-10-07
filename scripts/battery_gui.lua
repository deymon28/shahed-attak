local defense = require("scripts.defense")
local battery_gui = {}
local FRAME = "shahed-attack-battery-mode"
local SELECTOR = "shahed-attack-battery-mode-selection"
local MODES = {"ballistic", "both", "drones"}

local function opened_battery(player)
  if not player or player.opened_gui_type ~= defines.gui_type.entity then return nil end
  local entity = player.opened
  if entity and entity.valid and entity.name == "shahed-attack-abm-battery" then return entity end
end

local function mode_index(battery)
  local mode = defense.get_mode(battery)
  for index, name in ipairs(MODES) do if mode == name then return index end end
  return 1
end

local function can_edit(player, battery)
  return battery.operable and player.force.index == battery.force.index
end

function battery_gui.on_closed(event)
  local player = game.get_player(event.player_index)
  local frame = player and player.gui.relative[FRAME]
  if frame then frame.destroy() end
end

function battery_gui.on_opened(event)
  battery_gui.on_closed(event)
  local player = game.get_player(event.player_index)
  local battery = opened_battery(player)
  if not battery then return end
  local frame = player.gui.relative.add({
    type="frame", name=FRAME, direction="vertical", caption={"shahed-attack-gui.target-mode"},
    anchor={gui=defines.relative_gui_type.turret_gui, position=defines.relative_gui_position.right,
      name="shahed-attack-abm-battery"},
    tags={unit_number=battery.unit_number}
  })
  frame.add({type="drop-down", name=SELECTOR, selected_index=mode_index(battery),
    items={{"shahed-attack-gui.ballistic"},{"shahed-attack-gui.both"},{"shahed-attack-gui.drones"}},
    tooltip={"shahed-attack-gui.target-mode-description"}, enabled=can_edit(player,battery)})
end

function battery_gui.update()
  for _, player in pairs(game.players) do
    local frame = player.gui.relative[FRAME]
    if frame then
      local battery = opened_battery(player)
      if not battery or frame.tags.unit_number ~= battery.unit_number then
        frame.destroy()
      else
        frame[SELECTOR].selected_index = mode_index(battery)
        frame[SELECTOR].enabled = can_edit(player,battery)
      end
    end
  end
end

function battery_gui.on_selection_changed(event)
  local element = event.element
  if not element or not element.valid or element.name ~= SELECTOR then return end
  local player = game.get_player(event.player_index)
  local battery = opened_battery(player)
  local frame = player and player.gui.relative[FRAME]
  if not battery or not frame or frame[SELECTOR] ~= element
    or frame.tags.unit_number ~= battery.unit_number or not can_edit(player,battery) then return end
  defense.set_mode(battery, MODES[element.selected_index])
  battery_gui.update()
end

function battery_gui.initialize()
  for _, player in pairs(game.players) do battery_gui.on_opened({player_index=player.index}) end
end

return battery_gui
