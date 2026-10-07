local loaded=false
script.on_load(function() loaded=true end)
script.on_event(defines.events.on_tick,function(event)
  if not storage.setup then
    remote.call('shahed_abm_mode_test','setup')
    storage.setup=true
  end
  if remote.call('shahed_abm_mode_test','step',event.tick,loaded) then
    script.on_event(defines.events.on_tick,nil)
  end
end)
