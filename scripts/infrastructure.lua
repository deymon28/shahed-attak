-- Enemy airfields and ballistic launch sites. Every natural or scripted
-- attack starts at one of these registered, destructible sources.
local forces = require("scripts.forces")
local state = require("scripts.state")

local infrastructure = {}

local SOURCE_NAMES = {
  ["shahed-attack-airfield"] = "airfields",
  ["shahed-attack-ballistic-site"] = "ballistic_sites"
}

infrastructure.MAX_RANGE = {airfields = 3840, ballistic_sites = 8192}

local SCAN_CHUNKS_PER_UPDATE = 32

local PLACEMENT = {
  {name = "shahed-attack-airfield", salt = 17, chance = 0.18, min_distance = 384, spacing = 256, offset = 18},
  {name = "shahed-attack-ballistic-site", salt = 43, chance = 0.08, min_distance = 640, spacing = 512, offset = -18}
}

local function register_source(entity, source_type)
  local surface_state = state.ensure_surface(entity.surface)
  if not surface_state then
    return
  end
  local list = surface_state.sources[source_type]
  if list[entity.unit_number] then
    return
  end
  list[entity.unit_number] = entity
  local registration = script.register_on_object_destroyed(entity)
  state.root().source_registrations[registration] = {
    surface_index = entity.surface.index,
    source_type = source_type,
    unit_number = entity.unit_number
  }
end

local function deterministic_roll(surface, position, salt)
  local seed = surface.map_gen_settings.seed or 1
  local value = math.abs(seed + position.x * 73856093 + position.y * 19349663 + salt * 83492791)
  return (value % 10000) / 10000
end

local function decision_key(position, salt)
  return string.format("%d:%d:%d", math.floor(position.x), math.floor(position.y), salt)
end

local function decisions(surface_index)
  local root = state.root()
  root.source_decisions[surface_index] = root.source_decisions[surface_index] or {}
  return root.source_decisions[surface_index]
end

local function passes(surface, position, rule)
  local distance = math.sqrt(position.x * position.x + position.y * position.y)
  return distance >= rule.min_distance and deterministic_roll(surface, position, rule.salt) < rule.chance
end

local function place_source(surface, position, rule)
  local center = {x = position.x + rule.offset, y = position.y + rule.offset}
  local place = surface.find_non_colliding_position(rule.name, center, 48, 1)
  if not place then
    return nil
  end
  local entity = surface.create_entity({name = rule.name, position = place, force = forces.get(), raise_built = true})
  if entity then
    register_source(entity, SOURCE_NAMES[rule.name])
    local current = state.ensure_surface(surface)
    current.counters.sources_generated = current.counters.sources_generated + 1
  end
  return entity
end

-- Only spawners that win the deterministic roll are remembered, so a
-- destroyed source never comes back while storage stays small.
local function inspect_spawner(surface, spawner)
  if not spawner.valid then
    return
  end
  local remembered = decisions(surface.index)
  local position = spawner.position
  for _, rule in ipairs(PLACEMENT) do
    if passes(surface, position, rule) then
      local key = decision_key(position, rule.salt)
      if not remembered[key] then
        remembered[key] = true
        if surface.count_entities_filtered({position = position, radius = rule.spacing, name = rule.name}) == 0 then
          place_source(surface, position, rule)
        end
      end
    end
  end
end

local function inspect_area(surface, area)
  local spawners = surface.find_entities_filtered({area = area, type = "unit-spawner", force = "enemy"})
  table.sort(spawners, function(a, b) return a.unit_number < b.unit_number end)
  for _, spawner in ipairs(spawners) do
    inspect_spawner(surface, spawner)
  end
end

-- Schema 5 remembered every inspected spawner by unit number. Keep the
-- decisions that matter (spawners that passed a roll) and drop the rest.
local function migrate_inspected(root)
  local legacy = root.source_inspected
  if not legacy then
    return
  end
  for _, surface in pairs(game.surfaces) do
    if state.supported(surface) then
      local remembered = decisions(surface.index)
      for _, spawner in ipairs(surface.find_entities_filtered({type = "unit-spawner", force = "enemy"})) do
        if legacy[spawner.unit_number] then
          for _, rule in ipairs(PLACEMENT) do
            if passes(surface, spawner.position, rule) then
              remembered[decision_key(spawner.position, rule.salt)] = true
            end
          end
        end
      end
    end
  end
  root.source_inspected = nil
end

function infrastructure.initialize()
  local root = state.root()
  migrate_inspected(root)
  for _, surface in pairs(game.surfaces) do
    if state.supported(surface) then
      for name, source_type in pairs(SOURCE_NAMES) do
        for _, entity in ipairs(surface.find_entities_filtered({name = name})) do
          register_source(entity, source_type)
        end
      end
      if not root.source_scan_queue[surface.index] then
        local chunks = {}
        for chunk in surface.get_chunks() do
          chunks[#chunks + 1] = {x = chunk.x, y = chunk.y}
        end
        root.source_scan_queue[surface.index] = {chunks = chunks, cursor = 1}
      end
    end
  end
end

function infrastructure.on_entity_created(entity)
  local source_type = entity and entity.valid and SOURCE_NAMES[entity.name]
  if source_type then
    register_source(entity, source_type)
  end
end

function infrastructure.on_object_destroyed(event)
  local root = state.root()
  local record = root.source_registrations[event.registration_number]
  if not record then
    return
  end
  root.source_registrations[event.registration_number] = nil
  local surface_state = state.get_surface(record.surface_index)
  if surface_state and surface_state.sources[record.source_type] then
    surface_state.sources[record.source_type][record.unit_number] = nil
  end
end

function infrastructure.on_chunk_generated(event)
  if state.supported(event.surface) then
    inspect_area(event.surface, event.area)
  end
end

function infrastructure.on_biter_base_built(event)
  local entity = event.entity
  if entity and entity.valid and entity.type == "unit-spawner" and state.supported(entity.surface) then
    inspect_spawner(entity.surface, entity)
  end
end

function infrastructure.update()
  local root = state.root()
  for surface_index, queue in pairs(root.source_scan_queue) do
    local surface = game.get_surface(surface_index)
    if not state.supported(surface) then
      root.source_scan_queue[surface_index] = nil
    else
      for _ = 1, SCAN_CHUNKS_PER_UPDATE do
        local chunk = queue.chunks[queue.cursor]
        if not chunk then
          root.source_scan_queue[surface_index] = nil
          break
        end
        inspect_area(surface, {{chunk.x * 32, chunk.y * 32}, {(chunk.x + 1) * 32, (chunk.y + 1) * 32}})
        queue.cursor = queue.cursor + 1
      end
    end
  end
end

local function squared_distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

-- Valid sources able to reach the target, nearest first.
function infrastructure.sources_in_range(surface_state, source_type, target_position)
  local maximum = infrastructure.MAX_RANGE[source_type] or 3840
  local result = {}
  for _, entity in pairs(surface_state.sources[source_type] or {}) do
    if entity.valid and squared_distance(entity.position, target_position) <= maximum * maximum then
      result[#result + 1] = entity
    end
  end
  table.sort(result, function(a, b)
    local da, db = squared_distance(a.position, target_position), squared_distance(b.position, target_position)
    if da == db then return a.unit_number < b.unit_number end
    return da < db
  end)
  return result
end

-- The nearest source usually launches; sometimes a farther one does.
function infrastructure.get_source(surface_state, source_type, target_position, generator)
  local candidates = infrastructure.sources_in_range(surface_state, source_type, target_position)
  if #candidates == 0 then
    return nil
  end
  if #candidates > 1 and generator and generator:next_float() < 0.25 then
    return candidates[generator:range_int(1, #candidates)]
  end
  return candidates[1]
end

-- Source of a type closest to a position, within a radius (scripted events).
function infrastructure.source_near(surface_state, source_type, position, radius)
  local best, best_distance
  for _, entity in pairs(surface_state.sources[source_type] or {}) do
    if entity.valid then
      local distance = squared_distance(entity.position, position)
      if distance <= radius * radius and (not best_distance or distance < best_distance) then
        best, best_distance = entity, distance
      end
    end
  end
  return best
end

function infrastructure.count(surface_state, source_type)
  local count = 0
  for _, entity in pairs(surface_state.sources[source_type] or {}) do
    if entity.valid then count = count + 1 end
  end
  return count
end

return infrastructure
