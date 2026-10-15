-- Registry of attackable player structures, sampled when planning attacks.
-- Lists are compact arrays: a destroyed entity is replaced by the last entry,
-- so storage does not grow with construction churn and every sample is live.
local state = require("scripts.state")

local targeting = {}

local TYPE_WEIGHTS = {
  ["rocket-silo"] = 100,
  reactor = 80,
  lab = 50,
  roboport = 50,
  locomotive = 45,
  ["artillery-wagon"] = 40,
  ["assembling-machine"] = 25,
  furnace = 25,
  ["mining-drill"] = 25,
  generator = 25,
  ["cargo-wagon"] = 20,
  ["fluid-wagon"] = 20,
  ["solar-panel"] = 15,
  accumulator = 15,
  ["electric-pole"] = 10
}

local TARGET_TYPES = {}
for entity_type in pairs(TYPE_WEIGHTS) do TARGET_TYPES[#TARGET_TYPES + 1] = entity_type end
table.sort(TARGET_TYPES)
targeting.TARGET_TYPES = TARGET_TYPES

local ROLLING_STOCK = {
  locomotive = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true
}

targeting.DEFENSE_NAMES = {
  "shahed-attack-aa-turret",
  "shahed-attack-early-warning-radar",
  "shahed-attack-abm-battery",
  "shahed-attack-aa-wagon",
  "shahed-attack-abm-wagon"
}

local EXCLUDED_FORCES = {enemy = true, neutral = true, ["shahed-attack-enemy"] = true}

local SCAN_CHUNKS_PER_UPDATE = 8

function targeting.base_weight(entity_type, entity_name)
  if entity_name == "substation" then
    return 50
  end
  return TYPE_WEIGHTS[entity_type] or 0
end

function targeting.score(base_weight, activity, pollution_factor)
  if not base_weight or base_weight <= 0 then
    return 0
  end
  local pollution = 1 + math.max(0, math.min(0.5, (pollution_factor or 0) * 0.5))
  return base_weight * (activity or 1) * pollution
end

function targeting.is_rolling_stock(entity)
  return entity ~= nil and entity.valid and ROLLING_STOCK[entity.type] == true
end

function targeting.is_target(entity)
  return entity ~= nil and entity.valid and targeting.base_weight(entity.type, entity.name) > 0
    and entity.force ~= nil and not EXCLUDED_FORCES[entity.force.name]
    and state.supported(entity.surface)
end

local function force_list(surface_index, force_index, create)
  local root = state.root()
  local surface_targets = root.targets[surface_index]
  if not surface_targets then
    if not create then return nil end
    surface_targets = {}
    root.targets[surface_index] = surface_targets
  end
  local list = surface_targets[force_index]
  if not list and create then
    list = {entities = {}, units = {}, by_unit = {}}
    surface_targets[force_index] = list
  end
  return list
end

local function remove_unit(list, unit_number)
  local index = list.by_unit[unit_number]
  if not index then
    return
  end
  local last = #list.entities
  if index ~= last then
    list.entities[index] = list.entities[last]
    list.units[index] = list.units[last]
    list.by_unit[list.units[index]] = index
  end
  list.entities[last] = nil
  list.units[last] = nil
  list.by_unit[unit_number] = nil
end

function targeting.register(entity)
  if not targeting.is_target(entity) or not entity.unit_number then
    return false
  end
  local list = force_list(entity.surface.index, entity.force.index, true)
  if list.by_unit[entity.unit_number] then
    return false
  end
  local index = #list.entities + 1
  list.entities[index] = entity
  list.units[index] = entity.unit_number
  list.by_unit[entity.unit_number] = index
  local registration = script.register_on_object_destroyed(entity)
  state.root().target_registrations[registration] = {
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    unit_number = entity.unit_number
  }
  return true
end

function targeting.on_entity_created(entity)
  targeting.register(entity)
end

function targeting.on_object_destroyed(event)
  local root = state.root()
  local record = root.target_registrations[event.registration_number]
  if not record then
    return
  end
  root.target_registrations[event.registration_number] = nil
  local list = force_list(record.surface_index, record.force_index, false)
  if list then
    remove_unit(list, record.unit_number)
  end
end

-- Schema 5 lists kept destroyed entries as `false`; rebuild them compactly.
local function compact_legacy_lists()
  for _, surface_targets in pairs(state.root().targets) do
    for force_index, list in pairs(surface_targets) do
      if list.entries then
        local compact = {entities = {}, units = {}, by_unit = {}}
        for _, entity in pairs(list.entries) do
          if entity and entity.valid and entity.unit_number and not compact.by_unit[entity.unit_number] then
            local index = #compact.entities + 1
            compact.entities[index] = entity
            compact.units[index] = entity.unit_number
            compact.by_unit[entity.unit_number] = index
          end
        end
        surface_targets[force_index] = compact
      end
    end
  end
end

function targeting.queue_surface_scan(surface)
  if not state.supported(surface) then
    return
  end
  local root = state.root()
  if root.scan_queue[surface.index] then
    return
  end
  local chunks = {}
  for chunk in surface.get_chunks() do
    chunks[#chunks + 1] = {x = chunk.x, y = chunk.y}
  end
  root.scan_queue[surface.index] = {chunks = chunks, cursor = 1}
end

function targeting.initialize()
  compact_legacy_lists()
  for _, surface in pairs(game.surfaces) do
    targeting.queue_surface_scan(surface)
  end
end

local function scan_chunk(surface, chunk)
  local area = {{chunk.x * 32, chunk.y * 32}, {(chunk.x + 1) * 32, (chunk.y + 1) * 32}}
  for _, entity in ipairs(surface.find_entities_filtered({area = area, type = TARGET_TYPES})) do
    targeting.register(entity)
  end
end

function targeting.update()
  local root = state.root()
  for surface_index, queue in pairs(root.scan_queue) do
    local surface = game.get_surface(surface_index)
    if not surface then
      root.scan_queue[surface_index] = nil
    else
      for _ = 1, SCAN_CHUNKS_PER_UPDATE do
        local chunk = queue.chunks[queue.cursor]
        if not chunk then
          root.scan_queue[surface_index] = nil
          break
        end
        scan_chunk(surface, chunk)
        queue.cursor = queue.cursor + 1
      end
    end
  end
end

local function activity(entity)
  if ROLLING_STOCK[entity.type] then
    -- Trains waiting at stations are far easier to hit than moving ones.
    local train = entity.train
    return (train and train.speed == 0) and 1.5 or 0.6
  end
  local status = entity.status
  return (status == defines.entity_status.working or status == defines.entity_status.normal) and 1.5 or 1
end

local function entity_score(surface, entity)
  local pollution = math.min(surface.get_pollution(entity.position) / 200, 1)
  return targeting.score(targeting.base_weight(entity.type, entity.name), activity(entity), pollution)
end

local function best_candidate(surface, candidates, excluded, generator)
  local best_entity
  local best_score = -1
  for _, entity in ipairs(candidates) do
    if targeting.is_target(entity) and not (excluded and excluded[entity.unit_number]) then
      targeting.register(entity)
      local variation = generator and generator:range_float(0.8, 1.2) or 1
      local value = entity_score(surface, entity) * variation
      if value > best_score then
        best_entity = entity
        best_score = value
      end
    end
  end
  return best_entity
end

function targeting.choose_near_position(surface, force, position, radius)
  local candidates = surface.find_entities_filtered({
    position = position, radius = radius or 8, force = force, type = TARGET_TYPES
  })
  return best_candidate(surface, candidates, nil, nil)
end

function targeting.choose_distinct_near_position(surface, force, position, radius, excluded, generator)
  local candidates = surface.find_entities_filtered({
    position = position, radius = radius or 96, force = force, type = TARGET_TYPES
  })
  return best_candidate(surface, candidates, excluded or {}, generator)
end

function targeting.choose(surface, force, generator, intelligence)
  local list = force_list(surface.index, force.index, false)
  if not list or #list.entities == 0 then
    return nil
  end
  local entities = list.entities
  local attempts = math.min(intelligence and 512 or 128, #entities)
  local best_entity
  local best_score = -1
  for _ = 1, attempts do
    local entity = entities[generator:range_int(1, #entities)]
    if entity and entity.valid then
      local value = entity_score(surface, entity)
      if value > best_score then
        best_entity = entity
        best_score = value
      end
    end
  end
  return best_entity
end

-- Air-defense positions near a target, for suppression missions and for
-- sizing raids against known defenses.
function targeting.find_defenses(surface, force, position, radius)
  return surface.find_entities_filtered({
    position = position, radius = radius, force = force, name = targeting.DEFENSE_NAMES
  })
end

function targeting.get_candidate_forces(surface)
  local result = {}
  local surface_targets = state.root().targets[surface.index] or {}
  for force_index, list in pairs(surface_targets) do
    if list.entities and #list.entities > 0 then
      local force = game.forces[force_index]
      if force and force.valid and not EXCLUDED_FORCES[force.name] then
        result[#result + 1] = force
      end
    end
  end
  table.sort(result, function(a, b) return a.index < b.index end)
  return result
end

-- After game.merge_forces the absorbed force's buildings belong to the
-- destination force: drop the old lists and rescan every surface.
function targeting.on_forces_merged(source_index)
  local root = state.root()
  for _, surface_targets in pairs(root.targets) do
    surface_targets[source_index] = nil
  end
  for registration, record in pairs(root.target_registrations) do
    if record.force_index == source_index then root.target_registrations[registration] = nil end
  end
  for _, surface in pairs(game.surfaces) do
    root.scan_queue[surface.index] = nil
    targeting.queue_surface_scan(surface)
  end
end

function targeting.count(surface_index, force_index)
  local list = force_list(surface_index, force_index, false)
  return list and #list.entities or 0
end

return targeting
