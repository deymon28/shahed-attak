-- Coverage circles of air-defense positions on the map view.
-- Each player chooses whether to see defense ranges and radar ranges.
local config = require("scripts.lib.config")
local rules = require("scripts.lib.air_rules")
local state = require("scripts.state")

local range_overlay = {}

local RANGES = {
  ["shahed-attack-aa-turret"] = {radius = rules.AA_TURRET_RANGE, color = {r = 0.25, g = 0.7, b = 1}, kind = "defense"},
  ["shahed-attack-aa-wagon"] = {radius = rules.AA_WAGON_RANGE, color = {r = 0.25, g = 0.7, b = 1}, kind = "defense"},
  ["shahed-attack-abm-battery"] = {radius = rules.ABM_RANGE, color = {r = 1, g = 0.55, b = 0.1}, kind = "defense"},
  ["shahed-attack-abm-wagon"] = {radius = rules.ABM_WAGON_RANGE, color = {r = 1, g = 0.55, b = 0.1}, kind = "defense"},
  ["shahed-attack-early-warning-radar"] = {radius = rules.DRONE_RADAR_RANGE, color = {r = 0.3, g = 1, b = 0.4}, kind = "radar"}
}
range_overlay.RANGES = RANGES

local SETTINGS = {
  defense = "shahed-attack-show-defense-ranges",
  radar = "shahed-attack-show-radar-ranges"
}

local function viewers(force, kind)
  local result = {}
  for _, player in pairs(force.players) do
    if config.player(player, SETTINGS[kind]) then
      result[#result + 1] = player
    end
  end
  return result
end

local function apply_viewers(record, players)
  for _, render in ipairs({record.fill, record.outline}) do
    if render and render.valid then
      render.visible = #players > 0
      if #players > 0 then render.players = players end
    end
  end
end

local function destroy_record(root, unit_number)
  local record = root.range_renders[unit_number]
  if not record then
    return
  end
  for _, render in ipairs({record.fill, record.outline}) do
    if render and render.valid then render.destroy() end
  end
  root.range_renders[unit_number] = nil
end

function range_overlay.add(entity)
  local spec = entity and entity.valid and RANGES[entity.name]
  if not spec or not state.supported(entity.surface) then
    return
  end
  local root = state.root()
  local record = root.range_renders[entity.unit_number]
  if record and record.outline and record.outline.valid then
    return
  end
  local players = viewers(entity.force, spec.kind)
  local color = spec.color
  record = {
    kind = spec.kind,
    force_index = entity.force.index,
    fill = rendering.draw_circle({
      color = {r = color.r * 0.12, g = color.g * 0.12, b = color.b * 0.12, a = 0.12},
      radius = spec.radius, filled = true, target = entity, surface = entity.surface,
      render_mode = "chart", visible = false
    }),
    outline = rendering.draw_circle({
      color = {r = color.r, g = color.g, b = color.b, a = 0.8},
      radius = spec.radius, width = 2, filled = false, target = entity, surface = entity.surface,
      render_mode = "chart", visible = false
    })
  }
  root.range_renders[entity.unit_number] = record
  root.range_registrations[script.register_on_object_destroyed(entity)] = entity.unit_number
  apply_viewers(record, players)
end

function range_overlay.on_object_destroyed(event)
  local root = state.root()
  local unit_number = root.range_registrations[event.registration_number]
  if unit_number then
    root.range_registrations[event.registration_number] = nil
    destroy_record(root, unit_number)
  end
end

-- Re-applies visibility after a setting, force or player change.
function range_overlay.refresh()
  local root = state.root()
  local cache = {}
  for unit_number, record in pairs(root.range_renders) do
    if not (record.outline and record.outline.valid) then
      destroy_record(root, unit_number)
    else
      local force = game.forces[record.force_index]
      if force then
        local key = record.force_index .. ":" .. record.kind
        cache[key] = cache[key] or viewers(force, record.kind)
        apply_viewers(record, cache[key])
      end
    end
  end
end

function range_overlay.initialize()
  for _, surface in pairs(game.surfaces) do
    if state.supported(surface) then
      local names = {}
      for name in pairs(RANGES) do names[#names + 1] = name end
      for _, entity in ipairs(surface.find_entities_filtered({name = names})) do
        range_overlay.add(entity)
      end
    end
  end
  range_overlay.refresh()
end

function range_overlay.on_setting_changed(event)
  if event.setting == SETTINGS.defense or event.setting == SETTINGS.radar then
    range_overlay.refresh()
  end
end

return range_overlay
