local surface
local powered = {}

local function create(name, position, direction, force)
  local entity = surface.create_entity({name=name, position=position,
    direction=direction or defines.direction.north, force=force or "player", raise_built=true})
  assert(entity, "Could not create shadow review entity: " .. name)
  entity.destructible = false
  return entity
end

script.on_init(function()
  surface = game.surfaces[1]
  surface.always_day = true
  surface.request_to_generate_chunks({0,0}, 3)
  surface.force_generate_chunk_requests()
  for _, entity in ipairs(surface.find_entities_filtered({area={{-28,-24},{28,24}},
    type={"tree","simple-entity","cliff"}})) do entity.destroy() end
  local tiles = {}
  for x=-26,26 do for y=-22,22 do
    tiles[#tiles+1] = {name="refined-concrete", position={x,y}}
  end end
  surface.set_tiles(tiles)
  for index, direction in ipairs({defines.direction.north, defines.direction.east,
    defines.direction.south, defines.direction.west}) do
    local x = -12 + (index-1)*7
    create("shahed-attack-aa-turret", {x,-9}, direction)
    powered[#powered+1] = create("shahed-attack-abm-battery", {x,-3}, direction)
  end
  powered[#powered+1] = create("shahed-attack-early-warning-radar", {-11,4})
  create("gun-turret", {-3,4})
  powered[#powered+1] = create("radar", {5,4})
  create("shahed-attack-airfield", {-10,11}, nil, "enemy")
  create("shahed-attack-ballistic-site", {4,11}, nil, "enemy")
end)

script.on_event(defines.events.on_tick, function(event)
  for _, entity in ipairs(powered) do entity.energy = 20000000 end
  if event.tick == 40 or event.tick == 160 then
    game.take_screenshot({surface=surface, position={0,2}, resolution={1800,1500},
      zoom=1.5, path="structure-shadows-" .. event.tick .. ".png", show_entity_info=false})
  end
  if event.tick == 240 then
    log("SHAHED_TEST_PASS structure shadows rendered for five building families and cardinal turret headings")
    script.on_event(defines.events.on_tick, nil)
  end
end)
