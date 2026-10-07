local function animation(name, filename, size, frame_count, line_length, speed)
  return {
    type = "animation",
    name = name,
    filename = "__shahed-attack__/graphics/entity/" .. filename,
    priority = "high",
    width = size,
    height = size,
    frame_count = frame_count,
    line_length = line_length,
    scale = size == 192 and 0.65 or 0.5,
    animation_speed = speed
  }
end

data:extend({
  animation("shahed-attack-airfield-overlay", "airfield-overlay-sheet.png", 320, 16, 4, 0.12),
  animation("shahed-attack-ballistic-site-overlay", "ballistic-site-overlay-sheet.png", 320, 16, 4, 0.12),
  animation("shahed-attack-ballistic-site-launch", "ballistic-site-launch-sheet.png", 320, 20, 5, 0.25),
  animation("shahed-attack-radar-alert", "radar-alert-overlay-sheet.png", 192, 12, 4, 0.2),
  animation("shahed-attack-abm-launch", "abm-battery-launch-sheet.png", 192, 12, 12, 0.25)
})

-- Each launch direction has its own oblique 3D view, aligned to the native head.
-- Keep the legacy name above for a launch already present in an upgraded save.
local directional_launches = {}
for direction = 0, 63 do
  local launch = animation("shahed-attack-abm-launch-" .. direction,
    "abm-battery-launch-sheet.png", 192, 12, 12, 0.25)
  -- LuaRendering multiplies its playback speed by this prototype speed.
  launch.animation_speed = 1
  launch.x = (direction % 2) * 12 * 192
  launch.y = math.floor(direction / 2) * 192
  directional_launches[#directional_launches + 1] = launch
end
data:extend(directional_launches)
