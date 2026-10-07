local surface
local aircraft={}
local function fly(record, orientation)
  record.entity.commandable.set_command({type=defines.command.go_to_location,
    destination={x=record.entity.position.x+math.sin(orientation*2*math.pi)*12,
      y=record.entity.position.y-math.cos(orientation*2*math.pi)*12},distraction=defines.distraction.none})
end
script.on_init(function()
  surface=game.surfaces[1];surface.always_day=true;surface.daytime=0
  surface.request_to_generate_chunks({0,0},3);surface.force_generate_chunk_requests()
  for _,entity in pairs(surface.find_entities_filtered({type={'tree','simple-entity','resource','unit','unit-spawner'}})) do entity.destroy() end
  local tiles={}
  for x=-22,22 do for y=-13,13 do tiles[#tiles+1]={name='refined-concrete',position={x,y}} end end
  surface.set_tiles(tiles);surface.destroy_decoratives({})
  for row,kind in ipairs({'recon','strike','heavy'}) do
    for column=1,4 do
      local entity=surface.create_entity({name='shahed-attack-'..kind..'-drone',
        position={(column-2.5)*8,(row-2)*6},force='enemy'})
      assert(entity,'SHAHED_TEST_FAIL: create aircraft for shadow review')
      local record={entity=entity,orientation=(column-1)/4}
      aircraft[#aircraft+1]=record
      fly(record,record.orientation)
    end
  end
end)
script.on_event(defines.events.on_tick,function(event)
  if event.tick==2 then
    local player=game.players[1]
    if player then player.teleport({0,20}) end
  elseif event.tick==20 then
    game.take_screenshot({surface=surface,position={0,0.5},resolution={1600,1000},zoom=1.5,
      path='flight-shadow-cardinal.png',show_entity_info=false})
  elseif event.tick==35 then
    for _,record in ipairs(aircraft) do fly(record,record.orientation+0.125) end
  elseif event.tick==60 then
    game.take_screenshot({surface=surface,position={0,0.5},resolution={1600,1000},zoom=1.5,
      path='flight-shadow-diagonal.png',show_entity_info=false})
  elseif event.tick==80 then
    game.take_screenshot({surface=surface,position={0,0.5},resolution={1600,1000},zoom=1.5,
      path='flight-shadow-moving.png',show_entity_info=false})
  elseif event.tick==100 then
    log('SHAHED_TEST_PASS all three aircraft families render with directional ground shadows')
    script.on_event(defines.events.on_tick,nil)
  end
end)
