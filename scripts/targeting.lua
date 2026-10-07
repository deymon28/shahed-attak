local targeting = {}

local TARGET_TYPES = {
  "assembling-machine",
  "furnace",
  "mining-drill",
  "lab",
  "reactor",
  "generator",
  "solar-panel",
  "accumulator",
  "electric-pole",
  "roboport",
  "rocket-silo"
}

local TYPE_WEIGHTS = {
  ["rocket-silo"] = 100,
  reactor = 80,
  lab = 50,
  roboport = 50,
  ["assembling-machine"] = 25,
  furnace = 25,
  ["mining-drill"] = 25,
  generator = 25,
  ["solar-panel"] = 15,
  accumulator = 15,
  ["electric-pole"] = 10
}

local function ensure_root()
  storage.shahed_attack = storage.shahed_attack or {}
  local root = storage.shahed_attack
  root.targets = root.targets or {}
  root.destroyed_registrations = root.destroyed_registrations or {}
  root.scan_queue = root.scan_queue or {}
  return root
end

function targeting.base_weight(entity_type, entity_name)
  if entity_name == "substation" then
    return 50
  end
  return TYPE_WEIGHTS[entity_type] or 0
end

function targeting.score(base_weight, is_working, pollution_factor)
  if not base_weight or base_weight <= 0 then
    return 0
  end
  local activity = is_working and 1.5 or 1
  local pollution = 1 + math.max(0, math.min(0.5, (pollution_factor or 0) * 0.5))
  return base_weight * activity * pollution
end

function targeting.initialize()
  ensure_root()

  for _, surface in pairs(game.surfaces) do
    targeting.queue_surface_scan(surface)
  end
end

function targeting.is_target(entity)
  return entity and entity.valid and targeting.base_weight(entity.type, entity.name) > 0
    and entity.force
    and entity.force.name ~= "enemy"
    and entity.force.name ~= "neutral"
    and entity.force.name ~= "shahed-attack-enemy"
end

function targeting.register(entity)
  if not targeting.is_target(entity) or not entity.unit_number then
    return false
  end
  local root = ensure_root()
  local surface_targets = root.targets[entity.surface.index]
  if not surface_targets then
    surface_targets = {}
    root.targets[entity.surface.index] = surface_targets
  end
  local force_targets = surface_targets[entity.force.index]
  if not force_targets then
    force_targets = {entries = {}, by_unit = {}}
    surface_targets[entity.force.index] = force_targets
  end
  if force_targets.by_unit[entity.unit_number] then
    return false
  end
  local index = #force_targets.entries + 1
  local registration = script.register_on_object_destroyed(entity)
  force_targets.entries[index] = entity
  force_targets.by_unit[entity.unit_number] = index
  root.destroyed_registrations[registration] = {
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    unit_number = entity.unit_number,
    index = index
  }
  return true
end

function targeting.on_entity_created(entity)
  targeting.register(entity)
end

function targeting.on_object_destroyed(event)
  local root = ensure_root()
  local record = root and root.destroyed_registrations and root.destroyed_registrations[event.registration_number]
  if not record then
    return
  end
  root.destroyed_registrations[event.registration_number] = nil
  local surface_targets = root.targets[record.surface_index]
  local force_targets = surface_targets and surface_targets[record.force_index]
  if force_targets then
    force_targets.entries[record.index] = false
    force_targets.by_unit[record.unit_number] = nil
  end
end

function targeting.queue_surface_scan(surface)
  local root = ensure_root()
  if root.scan_queue[surface.index] then
    return
  end
  local chunks = {}
  for chunk in surface.get_chunks() do
    chunks[#chunks + 1] = {x = chunk.x, y = chunk.y}
  end
  root.scan_queue[surface.index] = {chunks = chunks, cursor = 1}
end

local function scan_chunk(surface, chunk)
  local area = {
    {chunk.x * 32, chunk.y * 32},
    {(chunk.x + 1) * 32, (chunk.y + 1) * 32}
  }
  local entities = surface.find_entities_filtered({area = area, type = TARGET_TYPES})
  for _, entity in ipairs(entities) do
    targeting.register(entity)
  end
end

function targeting.update()
  local root = ensure_root()
  for surface_index, queue in pairs(root.scan_queue) do
    local surface = game.get_surface(surface_index)
    if not surface then
      root.scan_queue[surface_index] = nil
    else
      for _ = 1, 16 do
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

local function is_working(entity)
  return entity.status == defines.entity_status.working
    or entity.status == defines.entity_status.normal
end

local function entity_score(surface, entity)
  local pollution = math.min(surface.get_pollution(entity.position) / 200, 1)
  return targeting.score(
    targeting.base_weight(entity.type, entity.name),
    is_working(entity),
    pollution
  )
end

function targeting.choose_near_position(surface, force, position, radius)
  local candidates = surface.find_entities_filtered({
    position = position,
    radius = radius or 8,
    force = force,
    type = TARGET_TYPES
  })
  local best_entity
  local best_score = -1
  for _, entity in ipairs(candidates) do
    if targeting.is_target(entity) then
      targeting.register(entity)
      local value = entity_score(surface, entity)
      if value > best_score then
        best_entity = entity
        best_score = value
      end
    end
  end
  return best_entity
end

function targeting.choose_distinct_near_position(surface, force, position, radius, excluded, generator)
  local candidates = surface.find_entities_filtered({
    position = position,
    radius = radius or 96,
    force = force,
    type = TARGET_TYPES
  })
  local best_entity
  local best_score = -1
  for _, entity in ipairs(candidates) do
    if targeting.is_target(entity) and not excluded[entity.unit_number] then
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

function targeting.choose(surface, force, generator, intelligence)
  local root = ensure_root()
  local surface_targets = root.targets[surface.index]
  local force_targets = surface_targets and surface_targets[force.index]
  if not force_targets then
    return nil
  end

  local entries = force_targets.entries
  local attempts = math.min(intelligence and 512 or 128, math.max(#entries, 1))
  local best_entity
  local best_score = -1
  for _ = 1, attempts do
    local index = generator:range_int(1, math.max(#entries, 1))
    local entity = entries[index]
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

function targeting.get_candidate_forces(surface)
  local result = {}
  local surface_targets = ensure_root().targets[surface.index] or {}
  for force_index, data in pairs(surface_targets) do
    if #data.entries > 0 then
      local force = game.forces[force_index]
      if force and force.valid and force.name ~= "enemy" and force.name ~= "neutral" then
        result[#result + 1] = force
      end
    end
  end
  return result
end

return targeting
