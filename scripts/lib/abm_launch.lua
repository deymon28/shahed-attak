local geometry = require('scripts.lib.abm_launch_geometry')

local launch = {animation_speed=.6, frame_count=12, body_frames=8}
launch.handoff_ticks = math.ceil(launch.body_frames / launch.animation_speed)
launch.duration_ticks = math.ceil(launch.frame_count / launch.animation_speed)

function launch.direction_index(orientation)
  return math.floor((orientation or 0) * 64 + .5) % 64
end

function launch.geometry(direction)
  return geometry[direction]
end

function launch.position(origin, direction, elapsed)
  local phase = math.min(launch.body_frames, math.floor(math.max(0, elapsed) * launch.animation_speed))
  local offset = geometry[direction].positions[phase + 1]
  return {x=origin.x + offset.x, y=origin.y + offset.y}
end

return launch
