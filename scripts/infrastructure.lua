local state = require("scripts.state")
local forces = require("scripts.forces")

local infrastructure = {}

local SOURCE_NAMES = {
  ["shahed-attack-airfield"] = "airfields",
  ["shahed-attack-ballistic-site"] = "ballistic_sites"
}

local function root()
  storage.shahed_attack.source_registrations = storage.shahed_attack.source_registrations or {}
  storage.shahed_attack.source_scan_queue = storage.shahed_attack.source_scan_queue or {}
  storage.shahed_attack.source_inspected = storage.shahed_attack.source_inspected or {}
  return storage.shahed_attack
end

local function append_source(entity, source_type)
  local surface_state = state.ensure_surface(entity.surface)
  local list = surface_state.sources[source_type]
  for _, existing in pairs(list) do
    if existing and existing.valid and existing.unit_number == entity.unit_number then
      return
    end
  end
  local index = #list + 1
  list[index] = entity
  local registration = script.register_on_object_destroyed(entity)
  root().source_registrations[registration] = {
    surface_index = entity.surface.index,
    source_type = source_type,
    index = index
  }
end

function infrastructure.initialize()
  local data = root()
  for _, surface in pairs(game.surfaces) do
    state.ensure_surface(surface)
    for name, source_type in pairs(SOURCE_NAMES) do
      for _, entity in ipairs(surface.find_entities_filtered({name = name})) do
        append_source(entity, source_type)
      end
    end
    if not data.source_scan_queue[surface.index] then
      local chunks = {}
      for chunk in surface.get_chunks() do
        chunks[#chunks + 1] = {x = chunk.x, y = chunk.y}
      end
      data.source_scan_queue[surface.index] = {chunks = chunks, cursor = 1}
    end
  end
end

function infrastructure.on_entity_created(entity)
  local source_type = entity and entity.valid and SOURCE_NAMES[entity.name]
  if source_type then
    append_source(entity, source_type)
  end
end

function infrastructure.on_object_destroyed(event)
  local data = root()
  local record = data.source_registrations[event.registration_number]
  if not record then
    return
  end
  data.source_registrations[event.registration_number] = nil
  local surface_state = state.get_surface(record.surface_index)
  if surface_state and surface_state.sources[record.source_type] then
    surface_state.sources[record.source_type][record.index] = false
  end
end

local function deterministic_roll(surface, position, salt)
  local seed = surface.map_gen_settings.seed or 1
  local value = math.abs(seed + position.x * 73856093 + position.y * 19349663 + salt * 83492791)
  return (value % 10000) / 10000
end

local function source_exists_near(surface, position, name, radius)
  return surface.count_entities_filtered({position=position,radius=radius,name=name}) > 0
end

local function place_source(surface, position, name, offset)
  local center={x=position.x+offset,y=position.y+offset}
  local place=surface.find_non_colliding_position(name,center,48,1)
  if not place then return nil end
  local entity=surface.create_entity({name=name,position=place,force=forces.get(),raise_built=true})
  if entity then
    append_source(entity,SOURCE_NAMES[name])
    local current=state.ensure_surface(surface)
    current.counters.sources_generated=(current.counters.sources_generated or 0)+1
  end
  return entity
end

local function inspect_spawner(surface, spawner)
  if not spawner.valid or not spawner.unit_number then return end
  local data=root()
  if data.source_inspected[spawner.unit_number] then return end
  data.source_inspected[spawner.unit_number]=surface.index
  local position=spawner.position
  local distance=math.sqrt(position.x*position.x+position.y*position.y)
  if distance>=384 and deterministic_roll(surface,position,17)<0.18
    and not source_exists_near(surface,position,"shahed-attack-airfield",256) then
    place_source(surface,position,"shahed-attack-airfield",18)
  end
  -- Independent placement avoids airfields suppressing the rarer launch sites.
  if distance>=640 and deterministic_roll(surface,position,43)<0.08
    and not source_exists_near(surface,position,"shahed-attack-ballistic-site",512) then
    place_source(surface,position,"shahed-attack-ballistic-site",-18)
  end
end

local function inspect_area(surface, area)
  local spawners=surface.find_entities_filtered({area=area,type="unit-spawner",force="enemy"})
  table.sort(spawners,function(a,b) return a.unit_number<b.unit_number end)
  for _, spawner in ipairs(spawners) do inspect_spawner(surface,spawner) end
end

function infrastructure.on_chunk_generated(event)
  inspect_area(event.surface, event.area)
end

function infrastructure.on_biter_base_built(event)
  local entity = event.entity
  if entity and entity.valid and entity.type == "unit-spawner" then
    inspect_spawner(entity.surface, entity)
  end
end

function infrastructure.update()
  local data = root()
  for surface_index, queue in pairs(data.source_scan_queue) do
    local surface = game.get_surface(surface_index)
    if not surface then
      data.source_scan_queue[surface_index] = nil
    else
      for _ = 1, 32 do
        local chunk = queue.chunks[queue.cursor]
        if not chunk then
          data.source_scan_queue[surface_index] = nil
          break
        end
        inspect_area(surface, {
          {chunk.x * 32, chunk.y * 32},
          {(chunk.x + 1) * 32, (chunk.y + 1) * 32}
        })
        queue.cursor = queue.cursor + 1
      end
    end
  end
end

local function valid_sources(surface_state, source_type)
  local result = {}
  for _, entity in pairs(surface_state.sources[source_type] or {}) do
    if entity and entity.valid then
      result[#result + 1] = entity
    end
  end
  return result
end

function infrastructure.has_source(surface_state, source_type)
  return #valid_sources(surface_state, source_type) > 0
end

function infrastructure.get_source(surface_state, source_type, target_position, generator)
  local candidates = {}
  local maximum = source_type == "airfields" and 3840 or 8192
  for _, entity in ipairs(valid_sources(surface_state,source_type)) do
    local dx,dy=entity.position.x-target_position.x,entity.position.y-target_position.y
    if dx*dx+dy*dy<=maximum*maximum then candidates[#candidates+1]=entity end
  end
  if #candidates == 0 then
    return nil
  end
  local nearest
  local nearest_distance
  for _, entity in ipairs(candidates) do
    local dx = entity.position.x - target_position.x
    local dy = entity.position.y - target_position.y
    local distance = dx * dx + dy * dy
    if not nearest_distance or distance < nearest_distance then
      nearest = entity
      nearest_distance = distance
    end
  end
  if #candidates > 1 and generator:next_float() < 0.25 then
    return candidates[generator:range_int(1, #candidates)]
  end
  return nearest
end

function infrastructure.external_origin(target_position, generator, minimum, maximum)
  local angle = generator:range_float(0, math.pi * 2)
  local distance = generator:range_float(minimum or 240, maximum or 340)
  return {
    x = target_position.x + math.cos(angle) * distance,
    y = target_position.y + math.sin(angle) * distance
  }
end

return infrastructure
