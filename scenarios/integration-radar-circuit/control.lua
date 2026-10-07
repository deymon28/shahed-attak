local radar
local target
local original_mode
local phase = "initializing"
local phase_tick = 0
local air_latch_until = 0

local air_signal = {
  type = "virtual",
  name = "shahed-attack-air-raid-signal",
  quality = "normal"
}
local ballistic_signal = {
  type = "virtual",
  name = "shahed-attack-ballistic-signal",
  quality = "normal"
}
local red = defines.wire_connector_id.circuit_red
local green = defines.wire_connector_id.circuit_green

local function restore_setting()
  if original_mode then
    remote.call("shahed_attack", "set_alert_delivery", original_mode)
  end
end

local function fail(message)
  restore_setting()
  error("SHAHED_TEST_FAIL: " .. message)
end

local function status()
  local current = remote.call("shahed_attack", "get_surface_state", 1)
  if not current or not current.radar_signals or not current.radar_signals[1] then
    fail("radar signal status is unavailable")
  end
  return current.radar_signals[1]
end

local function signal_count(signal, connector)
  if not radar or not radar.valid then
    fail("visible radar became invalid before cleanup")
  end
  return radar.get_signal(signal, connector)
end

script.on_init(function()
  game.speed = 16
  local surface = game.surfaces[1]
  original_mode = settings.global["shahed-attack-alert-delivery"].value
  local changed = remote.call("shahed_attack", "set_alert_delivery", "both")
  if not changed or not changed.ok then
    fail("owning mod could not enable combined alert delivery")
  end

  radar = surface.create_entity({
    name = "shahed-attack-early-warning-radar",
    position = {0, 0},
    force = game.forces.player,
    raise_built = true
  })
  target = surface.create_entity({
    name = "assembling-machine-1",
    position = {0, 64},
    force = game.forces.player,
    raise_built = true
  })
  local substation = surface.create_entity({
    name = "substation",
    position = {4, 0},
    force = game.forces.player
  })
  local power_source = surface.create_entity({
    name = "electric-energy-interface",
    position = {7, 0},
    force = game.forces.player
  })
  if not radar or not target or not substation or not power_source then
    fail("could not create radar circuit fixtures")
  end
  radar.energy = 10000000
end)

script.on_event(defines.events.on_tick, function(event)
  if phase == "initializing" and event.tick >= 120 then
    local initial = status()
    if initial.air_count ~= 0 or initial.ballistic_count ~= 0 then
      fail("new radar relay did not start at zero")
    end
    game.surfaces[1].create_entity({name="shahed-attack-airfield",position={0,-120},force="enemy",raise_built=true})
    local result = remote.call("shahed_attack", "schedule_event", {
      kind = "raid", stagger=false,
      surface_index = 1,
      target_force_name = "player",
      target_position = target.position,
      origin_position = {x = 0, y = -120},
      size = 2
    })
    if not result or not result.ok then
      fail("could not create tracked raid")
    end
    phase = "waiting-for-air"
    phase_tick = event.tick
  elseif phase == "waiting-for-air"
    and event.tick % 60 == 1
    and event.tick >= phase_tick + 60
  then
    local air_red = signal_count(air_signal, red)
    local air_green = signal_count(air_signal, green)
    if air_red <= 0 or air_green <= 0 then
      local current = status()
      local drone_count = game.surfaces[1].count_entities_filtered({
        name = {
          "shahed-attack-recon-drone",
          "shahed-attack-strike-drone",
          "shahed-attack-heavy-drone"
        }
      })
      fail(string.format(
        "tracked drones were not published: red=%d green=%d stored=%d energy=%.0f drones=%d relays=%d",
        air_red,
        air_green,
        current.air_count,
        radar.energy,
        drone_count,
        game.surfaces[1].count_entities_filtered({name = "shahed-attack-radar-signal-relay"})
      ))
    end
    local surface = game.surfaces[1]
    for _, drone in ipairs(surface.find_entities_filtered({
      name = {
        "shahed-attack-recon-drone",
        "shahed-attack-strike-drone",
        "shahed-attack-heavy-drone"
      }
    })) do
      drone.destroy({raise_destroy = true})
    end
    phase = "waiting-for-latch"
    phase_tick = event.tick
  elseif phase == "waiting-for-latch" and event.tick % 60 == 1 and event.tick > phase_tick then
    local current = status()
    if current.air_count <= 0 or current.air_latch_until <= event.tick then
      fail("air signal did not remain latched after drones disappeared")
    end
    air_latch_until = current.air_latch_until
    phase = "checking-latch"
  elseif phase == "checking-latch" and event.tick % 60 == 1 then
    local air_red = signal_count(air_signal, red)
    local air_green = signal_count(air_signal, green)
    if event.tick <= air_latch_until then
      if air_red <= 0 or air_green <= 0 then
        fail("air signal cleared before the ten-second latch expired")
      end
    else
      if air_red ~= 0 or air_green ~= 0 then
        fail("air signal remained active after the latch expired")
      end
      game.surfaces[1].create_entity({name="shahed-attack-ballistic-site",position={-900,0},force="enemy",raise_built=true})
      local result = remote.call("shahed_attack", "schedule_event", {
        kind = "ballistic", source_position={x=-900,y=0},
        surface_index = 1,
        target_force_name = "player",
        target_position = target.position
      })
      if not result or not result.ok then
        fail("could not create tracked ballistic threat")
      end
      phase = "waiting-for-ballistic"
      phase_tick = event.tick
    end
  elseif phase == "waiting-for-ballistic" and event.tick % 60 == 1 then
    local ballistic_red = signal_count(ballistic_signal, red)
    local ballistic_green = signal_count(ballistic_signal, green)
    if ballistic_red > 0 and ballistic_green > 0 then
      local current = status()
      if not current.alerting then
        fail("radar visual alert state ignored a tracked ballistic threat")
      end
      local changed = remote.call("shahed_attack", "set_alert_delivery", "global-sound")
      if not changed or not changed.ok then
        fail("owning mod could not disable circuit delivery")
      end
      phase = "waiting-for-circuit-disable"
      phase_tick = event.tick
    elseif event.tick - phase_tick > 720 then
      fail("ballistic threat never entered radar circuit range")
    end
  elseif phase == "waiting-for-circuit-disable" and event.tick % 60 == 1 and event.tick > phase_tick then
    if signal_count(air_signal, red) ~= 0
      or signal_count(air_signal, green) ~= 0
      or signal_count(ballistic_signal, red) ~= 0
      or signal_count(ballistic_signal, green) ~= 0
    then
      fail("global-sound mode did not suppress radar circuit output")
    end
    if not status().alerting then
      fail("delivery preference incorrectly cleared radar alerting state")
    end
    radar.destroy({raise_destroy = true})
    phase = "waiting-for-cleanup"
    phase_tick = event.tick
  elseif phase == "waiting-for-cleanup" and event.tick >= phase_tick + 2 then
    local current = remote.call("shahed_attack", "get_surface_state", 1)
    if #current.radar_signals ~= 0 then
      fail("radar relay record survived visible radar destruction")
    end
    if game.surfaces[1].count_entities_filtered({name = "shahed-attack-radar-signal-relay"}) ~= 0 then
      fail("hidden radar relay entity survived visible radar destruction")
    end
    restore_setting()
    phase = "complete"
    log("SHAHED_TEST_PASS radar publishes both threats, latches detections, obeys delivery mode, and cleans up")
  end
end)
