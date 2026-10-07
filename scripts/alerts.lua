local alert_policy = require("scripts.lib.alert_policy")
local config = require("scripts.lib.config")

local alerts = {}
local WARNING_DURATION_TICKS = { [1] = 360, [2] = 270 }
local WARNING_SOUNDS = { [1] = "shahed-attack-air-raid-siren", [2] = "shahed-attack-ballistic-warning" }
local ALERT_ICONS = {
  ["air-raid"] = {type = "virtual", name = "shahed-attack-air-raid-signal"},
  ballistic = {type = "virtual", name = "shahed-attack-ballistic-signal"},
  default = {type = "item", name = "shahed-attack-early-warning-radar"}
}

local function user_setting(player, name, fallback)
  return config.player(player, name, fallback)
end

local function delivery_mode()
  return alert_policy.normalize(config.global("shahed-attack-alert-delivery"))
end

local function sound_event_key(request, player_index)
  return tostring(player_index) .. "::" .. request.alert_type .. "::" .. tostring(request.event_id)
end

local function should_play(request, player)
  if not request.sound or not request.alert_type or not request.event_id then
    return false
  end
  if not alert_policy.plays_global(
    delivery_mode(),
    user_setting(player, "shahed-attack-alert-sound", true)
  ) then
    return false
  end
  local events = storage.shahed_attack.alert_sound_events
  local key = sound_event_key(request, player.index)
  if events[key] then
    return false
  end
  events[key] = game.tick
  return true
end

function alerts.notify(request)
  if not request or not request.force or not request.force.valid then
    return
  end
  for _, player in pairs(request.force.connected_players) do
    if request.entity and request.entity.valid then
      player.add_custom_alert(
        request.entity,
        ALERT_ICONS[request.alert_type or "default"] or ALERT_ICONS.default,
        request.message,
        true
      )
    end
    if request.always_print or user_setting(player, "shahed-attack-verbose-alerts", true) then
      player.print(request.message)
    end
    if should_play(request, player) then
      local root = storage.shahed_attack
      root.pending_alert_sounds = root.pending_alert_sounds or {}
      local pending = root.pending_alert_sounds[player.index]
      local priority = request.alert_type == "ballistic" and 2 or 1
      if not pending or priority > pending.priority then
        root.pending_alert_sounds[player.index] = {path=request.sound,priority=priority,tick=game.tick}
      end
    end
  end
end

local function can_hear(player)
  return player and player.valid and player.connected and alert_policy.plays_global(
    delivery_mode(), user_setting(player, "shahed-attack-alert-sound", true))
end

local function play_warning(root, player, path, priority, tick)
  player.play_sound({path=path})
  root.alert_sound_playback[player.index] = {
    priority=priority, until_tick=tick + WARNING_DURATION_TICKS[priority]
  }
  root.alert_counters.global_warning_dispatches = root.alert_counters.global_warning_dispatches + 1
end

local function live_warning_priorities(root)
  local priorities = {}
  for _, surface in pairs(root.surfaces or {}) do
    for _, missile in pairs(surface.active_missiles or {}) do
      if missile.detected and not missile.intercepted and not missile.finished then
        priorities[missile.force_index] = 2
      end
    end
    for _, drone in pairs(surface.active_drones or {}) do
      if drone.entity and drone.entity.valid and drone.mission ~= "returning"
        and (surface.alerted_events or {})[drone.event_id] then
        priorities[drone.target_force_index] = priorities[drone.target_force_index] or 1
      end
    end
  end
  return priorities
end

function alerts.flush_sounds(tick)
  local root = storage.shahed_attack
  root.alert_sound_playback = root.alert_sound_playback or {}
  for player_index, pending in pairs(root.pending_alert_sounds or {}) do
    -- Collect a complete simulation tick so simultaneous ballistic warnings win.
    if tick > pending.tick then
      local player = game.get_player(player_index)
      if can_hear(player) then
        local active = root.alert_sound_playback[player_index]
        -- A ballistic escalation is immediate. Repeated or lower-priority
        -- warnings share the currently playing clip instead of stacking it.
        if not active or tick >= active.until_tick or pending.priority > active.priority then
          play_warning(root, player, pending.path, pending.priority, tick)
        end
      end
      root.pending_alert_sounds[player_index] = nil
    end
  end

  -- Repeat complete clips only while detected threats remain alive. Poll once
  -- per second for save/load, reconnect and unmute; otherwise only at clip ends.
  local candidates = {}
  for player_index, active in pairs(root.alert_sound_playback) do
    if tick >= active.until_tick then candidates[player_index] = true end
  end
  if tick % 60 == 0 then
    for _, player in pairs(game.connected_players or {}) do
      if not root.alert_sound_playback[player.index]
        and not (root.pending_alert_sounds or {})[player.index] then candidates[player.index] = true end
    end
  end
  if next(candidates) then
    local priorities = live_warning_priorities(root)
    for player_index in pairs(candidates) do
      local player = game.get_player(player_index)
      local priority = can_hear(player) and player.force and priorities[player.force.index]
      if priority then
        play_warning(root, player, WARNING_SOUNDS[priority], priority, tick)
      else
        root.alert_sound_playback[player_index] = nil
      end
    end
  end
end

function alerts.air_raid(force, entity, count, direction, event_id, seconds)
  alerts.notify({
    force = force,
    entity = entity,
    message = {"shahed-attack-message.air-raid", count, direction or "?", seconds or 0},
    sound = "shahed-attack-air-raid-siren",
    alert_type = "air-raid",
    event_id = event_id,
    always_print = false
  })
end

function alerts.recon_complete(force, entity)
  alerts.notify({
    force = force,
    entity = entity,
    message = {"shahed-attack-message.recon-complete"},
    always_print = true
  })
end

function alerts.ballistic(force, entity, seconds, target_position, event_id, direction)
  alerts.notify({
    force = force,
    entity = entity,
    message = {"shahed-attack-message.ballistic-warning", seconds, direction or "?"},
    sound = "shahed-attack-ballistic-warning",
    alert_type = "ballistic",
    event_id = event_id,
    position = target_position,
    always_print = true
  })
end

function alerts.intercept(force, entity, success, probability)
  local key = success and "shahed-attack-message.intercept-success" or "shahed-attack-message.intercept-failed"
  alerts.notify({
    force = force,
    entity = entity,
    message = {key, math.floor(probability * 100 + 0.5)},
    always_print = false
  })
end

function alerts.delivery_state(player)
  local mode = delivery_mode()
  return {
    mode = mode,
    global_sound_enabled = alert_policy.plays_global(
      mode,
      user_setting(player, "shahed-attack-alert-sound", true)
    ),
    circuit_enabled = alert_policy.publishes_circuit(mode)
  }
end

function alerts.update(tick)
  local root = storage.shahed_attack
  if not root or not root.alert_sound_events then
    return
  end
  local cutoff = tick - 36000
  for key, dispatched_tick in pairs(root.alert_sound_events) do
    if dispatched_tick < cutoff then
      root.alert_sound_events[key] = nil
    end
  end
end

return alerts
