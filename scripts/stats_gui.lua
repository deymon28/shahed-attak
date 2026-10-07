-- Air-war statistics window, toggled by a shortcut or /shahed-attack stats.
local director = require("scripts.director")
local infrastructure = require("scripts.infrastructure")
local rules = require("scripts.lib.air_rules")
local state = require("scripts.state")

local stats_gui = {}

local FRAME = "shahed-attack-stats"
local CLOSE = "shahed-attack-stats-close"
stats_gui.SHORTCUT = "shahed-attack-stats"

local ROWS = {
  "evolution", "ballistic-class", "next-raid", "next-ballistic",
  "active-drones", "active-missiles", "queued-launches", "airfields", "launch-sites",
  "raids", "drones-launched", "decoys-launched", "drones-destroyed", "drone-impacts",
  "ballistic-launched", "ballistic-intercepted", "ballistic-impacts",
  "interceptors-fired", "interceptor-misses", "flak-shots", "flak-hits"
}

local function duration(seconds)
  seconds = math.floor(seconds + 0.5)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function count(map)
  local result = 0
  for _ in pairs(map) do result = result + 1 end
  return result
end

local function nauvis()
  local surface = game.get_surface(state.SUPPORTED_SURFACE)
  return surface, surface and state.get_surface(surface.index)
end

local function values(player)
  local surface, current = nauvis()
  if not current then
    return nil
  end
  local counters = current.counters
  local schedule = director.schedule(surface, current)
  local available, reason = director.ballistic_available(surface, current, player.force, game.tick)
  local class
  if available then
    class = {"shahed-attack-stats.class-" .. rules.ballistic_class(director.ballistic_progress(surface))}
  else
    class = {"shahed-attack-stats.unavailable-" .. reason}
  end
  local queued = count(current.pending_events)
  return {
    evolution = string.format("%.0f%%", game.forces.enemy.get_evolution_factor(surface) * 100),
    ["ballistic-class"] = class,
    ["next-raid"] = duration(schedule.raid_seconds),
    ["next-ballistic"] = available and duration(schedule.ballistic_seconds) or "-",
    ["active-drones"] = tostring(count(current.active_drones)),
    ["active-missiles"] = tostring(count(current.active_missiles)),
    ["queued-launches"] = tostring(queued),
    airfields = tostring(infrastructure.count(current, "airfields")),
    ["launch-sites"] = tostring(infrastructure.count(current, "ballistic_sites")),
    raids = tostring(counters.raids),
    ["drones-launched"] = tostring(counters.drones_launched),
    ["decoys-launched"] = tostring(counters.decoys_launched),
    ["drones-destroyed"] = tostring(counters.drones_destroyed),
    ["drone-impacts"] = tostring(counters.drone_impacts),
    ["ballistic-launched"] = tostring(counters.ballistic),
    ["ballistic-intercepted"] = tostring(counters.intercepted),
    ["ballistic-impacts"] = tostring(counters.ballistic_impacts),
    ["interceptors-fired"] = tostring(counters.interceptor_launches),
    ["interceptor-misses"] = tostring(counters.interceptor_misses),
    ["flak-shots"] = tostring(counters.flak_shots),
    ["flak-hits"] = tostring(counters.flak_hits)
  }
end

local function fill(player, frame)
  local data = values(player)
  local grid = frame.content
  for _, row in ipairs(ROWS) do
    local label = grid["value-" .. row]
    if label then label.caption = data and data[row] or "-" end
  end
end

function stats_gui.open(player)
  if player.gui.screen[FRAME] then
    return
  end
  local frame = player.gui.screen.add({type = "frame", name = FRAME, direction = "vertical"})
  local title = frame.add({type = "flow", direction = "horizontal"})
  title.drag_target = frame
  title.add({type = "label", caption = {"shahed-attack-stats.title"}, style = "frame_title"}).drag_target = frame
  local filler = title.add({type = "empty-widget", style = "draggable_space_header"})
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  filler.drag_target = frame
  title.add({type = "sprite-button", name = CLOSE, sprite = "utility/close", style = "frame_action_button"})
  local grid = frame.add({type = "table", name = "content", column_count = 2})
  grid.style.horizontal_spacing = 24
  for _, row in ipairs(ROWS) do
    grid.add({type = "label", caption = {"shahed-attack-stats." .. row}})
    grid.add({type = "label", name = "value-" .. row, caption = "-"})
  end
  frame.auto_center = true
  fill(player, frame)
  player.set_shortcut_toggled(stats_gui.SHORTCUT, true)
end

function stats_gui.close(player)
  local frame = player.gui.screen[FRAME]
  if frame then frame.destroy() end
  player.set_shortcut_toggled(stats_gui.SHORTCUT, false)
end

function stats_gui.toggle(player)
  if player.gui.screen[FRAME] then
    stats_gui.close(player)
  else
    stats_gui.open(player)
  end
end

function stats_gui.on_shortcut(event)
  if event.prototype_name == stats_gui.SHORTCUT then
    local player = game.get_player(event.player_index)
    if player then stats_gui.toggle(player) end
  end
end

function stats_gui.on_click(event)
  local element = event.element
  if element and element.valid and element.name == CLOSE then
    local player = game.get_player(event.player_index)
    if player then stats_gui.close(player) end
  end
end

function stats_gui.update()
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.screen[FRAME]
    if frame then fill(player, frame) end
  end
end

return stats_gui
