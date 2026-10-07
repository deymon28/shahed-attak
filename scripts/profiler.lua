-- Optional per-handler timing for performance measurement.
-- remote.call("shahed_attack", "start_profiling") begins accumulating;
-- remote.call("shahed_attack", "stop_profiling") writes the average time
-- per game tick of every handler to factorio-current.log.
-- Timing never changes game state, so it is safe in multiplayer.
local profiler = {}

local active = false
local start_tick = 0
local timers = {}
local order = {}

local function timer(name)
  local entry = timers[name]
  if not entry then
    entry = game.create_profiler(true)
    timers[name] = entry
    order[#order + 1] = name
  end
  return entry
end

function profiler.wrap(name, handler)
  return function(event)
    if not active then
      return handler(event)
    end
    local entry = timer(name)
    entry.restart()
    handler(event)
    entry.stop()
  end
end

function profiler.start()
  for _, entry in pairs(timers) do entry.reset(); entry.stop() end
  active = true
  start_tick = game.tick
  return {ok = true, tick = start_tick}
end

function profiler.stop()
  if not active then
    return {ok = false, error = "not-running"}
  end
  active = false
  local ticks = math.max(1, game.tick - start_tick)
  table.sort(order)
  for _, name in ipairs(order) do
    local entry = timers[name]
    entry.divide(ticks)
    log({"", "SHAHED_PROFILE ", name, " per-tick ", entry})
  end
  log("SHAHED_PROFILE ticks " .. ticks)
  return {ok = true, ticks = ticks}
end

return profiler
