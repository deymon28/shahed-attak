-- Minimal Factorio runtime mocks for standalone Lua tests.
-- Run tests from the repository root: lua tests/test_<name>.lua
package.path = "./?.lua;" .. package.path

local harness = {checks = 0}

function harness.check(condition, message)
  harness.checks = harness.checks + 1
  if not condition then
    error(message or "check failed", 2)
  end
end

function harness.close(actual, expected, epsilon, message)
  harness.check(math.abs(actual - expected) <= (epsilon or 1e-6),
    string.format("%s: expected %s, got %s", message or "close", tostring(expected), tostring(actual)))
end

function harness.render(args)
  local object = {valid = true, args = args or {}}
  for key, value in pairs(args or {}) do object[key] = value end
  if object.visible == nil then object.visible = true end
  object.destroy = function() object.valid = false end
  harness.renders[#harness.renders + 1] = object
  return object
end

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function as_set(value)
  if value == nil then return nil end
  if type(value) ~= "table" then return {[value] = true} end
  local set = {}
  for _, item in ipairs(value) do set[item] = true end
  return set
end

local function force_matches(entity, force)
  if force == nil then return true end
  if type(force) == "string" then return entity.force and entity.force.name == force end
  return entity.force == force or (entity.force and force.index and entity.force.index == force.index)
end

function harness.surface(index, name)
  local surface = {
    index = index or 1, name = name or "nauvis", valid = true, entities = {}, created = {},
    ticks_per_day = 25000, map_gen_settings = {seed = 1, peaceful_mode = false}
  }
  function surface.find_entities_filtered(filter)
    local names, types = as_set(filter.name), as_set(filter.type)
    local result = {}
    for _, entity in ipairs(surface.entities) do
      if entity.valid and (not names or names[entity.name]) and (not types or types[entity.type])
        and force_matches(entity, filter.force)
        and (not filter.position or distance(entity.position, filter.position) <= (filter.radius or 0)) then
        result[#result + 1] = entity
      end
    end
    return result
  end
  function surface.count_entities_filtered(filter) return #surface.find_entities_filtered(filter) end
  function surface.create_entity(args)
    surface.created[#surface.created + 1] = args
    if harness.entity_factory then return harness.entity_factory(surface, args) end
    return {valid = true}
  end
  function surface.create_trivial_smoke() end
  function surface.play_sound() end
  function surface.get_pollution() return 0 end
  function surface.is_chunk_generated() return true end
  function surface.request_to_generate_chunks() end
  function surface.get_chunks() return function() return nil end end
  function surface.find_non_colliding_position(_, position) return position end
  return surface
end

function harness.force(index, name)
  local force = {index = index, name = name or ("force-" .. index), valid = true,
    connected_players = {}, players = {}, technologies = {}}
  function force.get_friend() return false end
  function force.get_cease_fire() return false end
  function force.get_evolution_factor() return harness.evolution end
  return force
end

function harness.inventory(items)
  local inventory = {items = items or {}}
  function inventory.get_item_count(name) return inventory.items[name] or 0 end
  function inventory.remove(stack)
    local available = inventory.items[stack.name] or 0
    local removed = math.min(available, stack.count or 1)
    inventory.items[stack.name] = available - removed
    return removed
  end
  return inventory
end

local next_unit = 1000
function harness.entity(spec)
  local entity = spec or {}
  if entity.valid == nil then entity.valid = true end
  if not entity.unit_number then
    next_unit = next_unit + 1
    entity.unit_number = next_unit
  end
  entity.position = entity.position or {x = 0, y = 0}
  entity.orientation = entity.orientation or 0
  entity.surface = entity.surface or harness.nauvis
  entity.force = entity.force or harness.player_force
  function entity.get_inventory() return entity.inventory end
  function entity.destroy() entity.valid = false; return true end
  function entity.die() entity.valid = false; return true end
  function entity.damage(amount) entity.damage_taken = (entity.damage_taken or 0) + amount end
  if entity.surface and entity.surface.entities then
    entity.surface.entities[#entity.surface.entities + 1] = entity
  end
  return entity
end

-- Resets globals and the module cache; returns the nauvis surface.
function harness.reset()
  for name in pairs(package.loaded) do
    if name:find("^scripts%.") then package.loaded[name] = nil end
  end
  harness.renders = {}
  harness.player_settings = {}
  harness.entity_factory = nil
  harness.evolution = 0
  local registrations = 0
  storage = {}
  settings = {global = {}, get_player_settings = function(player)
    return harness.player_settings[player.index] or {}
  end}
  defines = {
    inventory = {turret_ammo = 1, cargo_wagon = 2},
    entity_status = {working = 1, normal = 2},
    entity_status_diode = {green = 1, yellow = 2, red = 3},
    gui_type = {entity = 1},
    relative_gui_type = {turret_gui = 1, cargo_wagon_gui = 2},
    relative_gui_position = {right = 1},
    command = {go_to_location = 1, stop = 2, attack = 3},
    distraction = {none = 0}
  }
  script = {register_on_object_destroyed = function()
    registrations = registrations + 1
    return registrations
  end}
  rendering = {draw_sprite = harness.render, draw_light = harness.render,
    draw_animation = harness.render, draw_circle = harness.render}
  harness.nauvis = harness.surface(1, "nauvis")
  harness.player_force = harness.force(1, "player")
  harness.enemy_force = harness.force(2, "enemy")
  harness.air_force = harness.force(3, "shahed-attack-enemy")
  game = {
    tick = 0,
    surfaces = {harness.nauvis},
    forces = {player = harness.player_force, enemy = harness.enemy_force,
      ["shahed-attack-enemy"] = harness.air_force,
      [1] = harness.player_force, [2] = harness.enemy_force, [3] = harness.air_force},
    players = {}, connected_players = {}
  }
  function game.get_surface(key)
    for _, surface in pairs(game.surfaces) do
      if surface.index == key or surface.name == key then return surface end
    end
  end
  function game.get_player(index) return game.players[index] end
  function game.create_force() return harness.air_force end
  return harness.nauvis
end

-- A ready-made surface state for the nauvis mock.
function harness.surface_state()
  local state = require("scripts.state")
  state.initialize()
  return state.ensure_surface(harness.nauvis), state
end

function harness.pass(name)
  print(string.format("PASS: %s (%d checks)", name, harness.checks))
end

return harness
