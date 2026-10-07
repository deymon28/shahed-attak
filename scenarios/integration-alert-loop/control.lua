local started, surface, radar, target, quiet_count, ballistic_start
local function check(value, message) assert(value, 'SHAHED_TEST_FAIL: '..message) end
local function snapshot() return remote.call('shahed_attack','get_surface_state',surface.index) end
script.on_init(function() game.speed=4;log('ALERT_LOOP_TEST_INIT') end)
script.on_event(defines.events.on_tick, function(event)
  if not started then
    local player=game.players[1]
    if not player then
      if event.tick%600==0 then log('ALERT_LOOP_WAITING_FOR_PLAYER tick='..event.tick) end
      return
    end
    log('ALERT_LOOP_PLAYER connected='..tostring(player.connected)..' count='..#game.connected_players)
    if player.character then player.character.destructible=false end
    player.teleport({50,50})
    game.speed=4
    started=event.tick;surface=game.surfaces[1];surface.always_day=true
    surface.request_to_generate_chunks({0,0},4);surface.force_generate_chunk_requests()
    target=surface.create_entity({name='assembling-machine-1',position={0,0},force='player',raise_built=true})
    radar=surface.create_entity({name='shahed-attack-early-warning-radar',position={5,0},force='player',raise_built=true})
    remote.call('shahed_attack','set_alert_delivery','both')
  end
  if radar.valid then radar.energy=10000000 end
  local tick=event.tick-started
  local status=snapshot()
  if tick%600==0 then log('ALERT_LOOP_PROGRESS tick='..tick..' warnings='..status.global_warning_dispatches) end
  if tick==120 then
    check(status.global_warning_dispatches==0,'idle world has no global warning playback')
    check((status.audio_counters['shahed-attack-radar-ping'] or 0)==0,'idle radar does not dispatch beeps')
    check(remote.call('shahed_attack','schedule_event',{kind='recon',surface_index=surface.index,
      target_position=target.position,origin_position={x=-300,y=0},size=1}).ok,'spawn recon approach')
  elseif tick==1100 then
    check(status.global_warning_dispatches>=3,'single detected recon sustains multiple siren cycles')
    for _,drone in pairs(surface.find_entities_filtered({name='shahed-attack-recon-drone'})) do drone.die(game.forces.player) end
    quiet_count=status.global_warning_dispatches
  elseif tick==1600 then
    check(status.active_drones==0,'recon threat was removed')
    check(status.global_warning_dispatches==quiet_count,'siren stops repeating after recon destruction')
    local site=surface.create_entity({name='shahed-attack-ballistic-site',position={-1000,0},force='enemy',raise_built=true})
    check(remote.call('shahed_attack','schedule_event',{kind='ballistic',surface_index=surface.index,
      target_position=target.position,source_position=site.position}).ok,'launch ballistic threat')
    ballistic_start=status.global_warning_dispatches
  elseif tick==2500 then
    check(status.global_warning_dispatches>=ballistic_start+4,'one ballistic threat sustains repeated warning cycles')
  elseif tick==4450 then
    check(status.active_missiles==0 and status.ballistic_sound_sources==0,'ballistic flight and its looping source end')
    quiet_count=status.global_warning_dispatches
  elseif tick==4900 then
    check(status.global_warning_dispatches==quiet_count,'no global warning remains after the attack')
    log('SHAHED_TEST_PASS idle silence, repeated drone/ballistic warning cycles, and end-of-threat cleanup')
    script.on_event(defines.events.on_tick,nil)
  end
end)
