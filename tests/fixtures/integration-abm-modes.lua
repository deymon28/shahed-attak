-- Test-only bridge, appended by the integration harness to its temporary mod copy.
local mode_gui = require('scripts.battery_gui')
local mode_random = require('scripts.lib.random')
local function mode_check(value, message) assert(value, 'SHAHED_TEST_FAIL: '..message) end
local function mode_select(player, battery, index)
  player.teleport({x=battery.position.x,y=battery.position.y+5},battery.surface)
  player.opened=nil
  player.opened=battery
  mode_check(player.opened==battery,'fixture player opens the nearby battery')
  mode_gui.on_opened({player_index=player.index})
  local frame=player.gui.relative['shahed-attack-battery-mode']
  mode_check(frame and frame.valid,'real relative battery panel exists')
  mode_check(frame.anchor.gui==defines.relative_gui_type.turret_gui,'panel anchors to the native turret inventory')
  local dropdown=frame['shahed-attack-battery-mode-selection']
  mode_check(#dropdown.items==3,'real drop-down has all three modes')
  if index then
    dropdown.selected_index=index
    mode_gui.on_selection_changed({player_index=player.index,element=dropdown})
  end
  return dropdown.selected_index
end
remote.add_interface('shahed_abm_mode_test',{
  setup=function()
    local surface=game.surfaces[1]
    surface.always_day=true
    local test={batteries={},drones={},missiles={}}
    storage.abm_mode_test=test
    test.player=game.players[1]
    mode_check(test.player,'run the fixture with a real player')
    for index=1,3 do
      local x=(index-1)*600
      local target=surface.create_entity({name='assembling-machine-1',position={x,20},force='player',raise_built=true})
      local site=surface.create_entity({name='shahed-attack-ballistic-site',position={x-80,20},force='enemy',raise_built=true})
      local battery=surface.create_entity({name='shahed-attack-abm-battery',position={x,0},force='player',raise_built=true})
      mode_check(target and site and battery,'fixture entities created')
      battery.insert({name='shahed-attack-interceptor',count=20})
      battery.energy=20000000
      test.batteries[index]=battery
      mode_check(mode_select(test.player,battery)==1,'new battery defaults to ballistic-only')
      if index==2 then mode_select(test.player,battery,3) end
      if index==3 then mode_select(test.player,battery,2) end
      local generator=mode_random.new(1234+index)
      local id=raids.spawn_event(surface,game.forces.player,target,'raid',1,
        {force_external=true,generator=generator,origin_position={x=x-70,y=0}})
      mode_check(id,'spawn a real tracked Shahed')
      local current=state.get_surface(1)
      for unit,record in pairs(current.active_drones) do
        if record.event_id==id then
          -- Raids have a two-drone minimum; keep one target in each isolated test arena.
          if test.drones[index] then
            record.entity.destroy()
            current.active_drones[unit]=nil
          else test.drones[index]=record.entity end
        end
      end
      test.missiles[index]=ballistics.launch(surface,game.forces.player,target,site,generator)
    end
    settings.global['shahed-attack-intercept-accuracy']={value=1}
    mode_check(mode_select(test.player,test.batteries[2])==3,'independent drone-only choice is retained')
    local current=state.get_surface(1)
    test.next_raid_tick=current.next_raid_tick
    test.next_ballistic_day=current.next_ballistic_day
  end,
  step=function(tick,loaded)
    local test=storage.abm_mode_test
    if tick==10 and not loaded then
      game.take_screenshot({player=test.player,show_gui=true,resolution=test.player.display_resolution,path='abm-modes-gui.png'})
    end
    for _,battery in ipairs(test.batteries) do if battery.valid then battery.energy=20000000 end end
    local current=state.get_surface(1)
    if tick==30 and not loaded then
      local shots={}
      for _,shot in pairs(current.projectiles) do shots[shot.source.unit_number]=shot end
      local first,second,third=shots[test.batteries[1].unit_number],shots[test.batteries[2].unit_number],shots[test.batteries[3].unit_number]
      mode_check(first and first.target_missile_id==test.missiles[1],'default battery attacks ballistics')
      mode_check(second and second.target_drone==test.drones[2],'drone-only battery ignores simultaneous ballistics')
      mode_check(third and third.target_missile_id==test.missiles[3],'mixed battery prioritizes simultaneous ballistics')
      test.saved_shot_id=second.id
      game.auto_save('abm-modes-fixture')
    end
    if tick==31 and not loaded then log('SHAHED_RELOAD_READY') end
    if loaded and not test.checked_reload then
      mode_check(defense.get_mode(test.batteries[1])=='ballistic' and defense.get_mode(test.batteries[2])=='drones'
        and defense.get_mode(test.batteries[3])=='both','all per-battery modes survive real save/load')
      mode_check(current.projectiles[test.saved_shot_id].target_drone==test.drones[2],'in-flight drone reference survives save/load')
      mode_check(mode_select(test.player,test.batteries[2])==3,'reopened real GUI shows saved mode')
      test.checked_reload=true
    end
    if loaded and tick==40 then
      local cooldown=current.battery_next_shot[test.batteries[2].unit_number]
      mode_select(test.player,test.batteries[2],1)
      mode_check(current.battery_next_shot[test.batteries[2].unit_number]==cooldown,'GUI mode change preserves reload deadline')
      -- Keep the battery empty after its first launch so the newly enabled ballistic mode cannot consume another round.
      test.batteries[2].remove_item({name='shahed-attack-interceptor',count=100})
    end
    if loaded and tick==150 then
      mode_check(test.checked_reload,'save/load checks ran')
      mode_check(test.drones[1].valid,'ballistic-only battery leaves Shaheds alone')
      mode_check(not test.drones[2].valid,'launched drone interceptor finishes after GUI mode change')
      mode_check(not test.drones[3].valid,'mixed mode attacks Shaheds after ballistics')
      mode_check(current.active_missiles[test.missiles[2]],'drone-only battery did not shoot the ballistic missile')
      mode_check(current.counters.intercepted==2 and current.counters.interceptor_drone_hits==2,'separate ballistic and drone outcome accounting')
      mode_check(test.batteries[1].get_item_count('shahed-attack-interceptor')==19
        and test.batteries[3].get_item_count('shahed-attack-interceptor')==18,'one ammunition charge per real interception')
      mode_check(current.next_raid_tick==test.next_raid_tick and current.next_ballistic_day==test.next_ballistic_day,
        'target selection does not change raid schedules')
      local battery=test.batteries[3]
      local unit=battery.unit_number
      mode_select(test.player,battery)
      battery.destroy({raise_destroy=true})
      defense.update(tick)
      mode_gui.update()
      mode_check(not current.battery_modes[unit],'destroyed battery mode is cleaned up')
      mode_check(not test.player.gui.relative['shahed-attack-battery-mode'],'destroyed battery panel is removed')
      log('SHAHED_TEST_PASS native GUI, independent modes, priority, real drone interception, saved in-flight target and mode persistence')
      return true
    end
  end
})
