package.path = './?.lua;' .. package.path

local calls, entities, registrations = {}, {}, 0
storage = {shahed_attack = {}}
game = {tick = 100, surfaces = {}}
script = {register_on_object_destroyed = function()
  registrations = registrations + 1
  return registrations
end}
rendering = {draw_animation = function(args)
  local result = {valid = true, args = args}
  result.destroy = function() result.valid = false end
  calls[#calls + 1] = result
  return result
end}
local surface = {index = 1, name = "nauvis", valid = true, find_entities_filtered = function(filter)
  local found = {}
  for _, entity in ipairs(entities) do
    if entity.valid and entity.name == filter.name then found[#found + 1] = entity end
  end
  return found
end}
game.surfaces = {surface}
local function entity(name, id)
  local result = {name = name, unit_number = id, valid = true, surface = surface,
    position = {x = 0, y = 0}, orientation = 0}
  entities[#entities + 1] = result
  return result
end
local function reload()
  package.loaded['scripts.visual_effects'] = nil
  package.loaded['scripts.state'] = nil
  return require('scripts.visual_effects')
end
local effects = reload()
local silo = entity('shahed-attack-ballistic-site', 1)
local airfield = entity('shahed-attack-airfield', 2)
effects.initialize()
assert(effects.status(1).idle == 2)
local old_idle = storage.shahed_attack.visual_records[1].idle
local launch = effects.play_ballistic_launch(silo)
assert(not old_idle.valid and effects.status(1).idle == 1, 'Idle hatch must hide during launch')
effects.on_entity_created(silo)
assert(effects.status(1).idle == 1, 'Repeated registration must not restore the closed hatch')
game.tick = 140
effects = reload()
effects.initialize()
effects.update(game.tick)
assert(launch.valid and effects.status(1).idle == 1, 'Reload must preserve active launch')
game.tick = 179
effects.update(game.tick)
assert(launch.valid)
game.tick = 180
effects.update(game.tick)
assert(not launch.valid and effects.status(1).idle == 2, 'Idle must resume after launch')
assert(next(storage.shahed_attack.visual_active_launches) == nil)

local first = effects.play_ballistic_launch(silo)
game.tick = 200
local second = effects.play_ballistic_launch(silo)
assert(not first.valid and second.valid, 'New launch replaces the old animation')
game.tick = 260
effects.update(game.tick)
assert(second.valid and effects.status(1).idle == 1, 'Replacement has its own duration')
local registration = storage.shahed_attack.visual_records[1].registration
silo.valid = false
effects.on_object_destroyed({registration_number = registration})
assert(not second.valid and storage.shahed_attack.visual_records[1] == nil)
assert(next(storage.shahed_attack.visual_active_launches) == nil)
effects.update(300)
assert(effects.status(1).idle == 1)

local battery = entity('shahed-attack-abm-battery', 3)
local north = effects.play_abm_launch(battery, {x = 0, y = -10})
local east = effects.play_abm_launch(battery, {x = 10, y = 0})
local south = effects.play_abm_launch(battery, {x = 0, y = 10})
assert(north.args.animation == 'shahed-attack-abm-launch-0')
assert(east.args.animation == 'shahed-attack-abm-launch-16')
assert(south.args.animation == 'shahed-attack-abm-launch-32')
assert(not east.args.orientation, 'Use rendered geometry direction without rotating the image')
local animation_prototypes={}
data={extend=function(_,definitions)
  for _,definition in ipairs(definitions) do animation_prototypes[definition.name]=definition end
end}
dofile('prototypes/visuals.lua')
local prototype=animation_prototypes[east.args.animation]
local launch_timing=require('scripts.lib.abm_launch')
assert(math.abs(launch_timing.animation_speed * prototype.animation_speed * east.args.time_to_live - prototype.frame_count) < .000001,
  'Launch playback must show all twelve frames before the render expires')
assert(math.abs(game.tick * east.args.animation_speed + (east.args.animation_offset or 0)) < .000001,
  'The launch must begin at frame zero regardless of the current world tick')
assert(effects.status(1).abm_launches == 3)
print('PASS: visual launch lifecycle and directional effects')
