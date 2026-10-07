local surface, battery, first_shot, last_heading
local function check(value, message) assert(value, 'SHAHED_TEST_FAIL: '..message) end
script.on_init(function()
  surface=game.surfaces[1];surface.always_day=true
  surface.request_to_generate_chunks({0,0},4);surface.force_generate_chunk_requests()
  local target=surface.create_entity({name='assembling-machine-1',position={-20,0},force='player',raise_built=true})
  local site=surface.create_entity({name='shahed-attack-ballistic-site',position={100,0},force='enemy',raise_built=true})
  battery=surface.create_entity({name='shahed-attack-abm-battery',position={0,0},force='player',raise_built=true})
  battery.orientation=0;last_heading=0;battery.energy=20000000
  battery.insert({name='shahed-attack-interceptor',count=10})
  remote.call('shahed_attack','set_intercept_accuracy',0)
  check(remote.call('shahed_attack','schedule_event',{kind='ballistic',surface_index=1,target_position=target.position,source_position=site.position}).ok,'schedule ballistic target')
  game.surfaces[1].create_entity({name="shahed-attack-airfield",position={0,-6},force="enemy",raise_built=true})
  check(remote.call('shahed_attack','schedule_event',{kind='recon', stagger=false,surface_index=1,target_position=target.position,origin_position={x=0,y=-6},size=1}).ok,'schedule reconnaissance aircraft')
end)
script.on_event(defines.events.on_tick,function(event)
  battery.energy=20000000
  local state=remote.call('shahed_attack','get_surface_state',1)
  if not first_shot then
    local delta=math.abs((battery.orientation-last_heading+.5)%1-.5)
    check(delta<=1/60+.00001,'smooth bounded battery rotation')
    last_heading=battery.orientation
    if (state.counters.interceptor_launches or 0)>0 then
      first_shot=event.tick
      check(first_shot>=10 and first_shot<=32,'brief acquisition before actual launch')
      log('ABM first launch at tick ' .. first_shot)
      check(battery.get_item_count('shahed-attack-interceptor')==9,'single resource charge at launch')
    else check(battery.get_item_count('shahed-attack-interceptor')==10,'no ammunition spent while aiming') end
  end
  if event.tick==10 then
    local drones=surface.find_entities_filtered({name='shahed-attack-recon-drone'})
    check(#drones==1,'one recon aircraft');drones[1].die(game.forces.player)
  elseif event.tick==11 then
    local found=false
    for _,entity in pairs(surface.find_entities_filtered({type='projectile'})) do
      if entity.name:find('falling-recon-wreck',1,true) then found=true end
      check(not entity.name:find('shahed-attack-falling-wreck-',1,true),'recon must never use the strike wreck')
    end
    check(found,'recon wreck exists after actual death')
  end
  if event.tick==10 or event.tick==17 or event.tick==23 or event.tick==55 then
    game.take_screenshot({surface=surface,position={0,-3},resolution={1200,900},zoom=2.5,path='small-fixes-'..event.tick..'.png'})
  end
  if event.tick==120 then
    check(first_shot,'battery completed acquisition and launched')
    check((state.counters.wreck_safe or 0)+(state.counters.wreck_fuel or 0)+(state.counters.wreck_warhead or 0)==1,'recon wreck completed exactly once')
    log('SHAHED_TEST_PASS smoother ABM acquisition and correct recon falling model')
    script.on_event(defines.events.on_tick,nil)
  end
end)
