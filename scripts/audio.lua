local audio_policy = require("scripts.lib.audio_policy")

local audio = {}

local function ensure_root()
  storage.shahed_attack = storage.shahed_attack or {}
  local root = storage.shahed_attack
  root.audio_cooldowns = root.audio_cooldowns or {}
  root.audio_counters = root.audio_counters or {}
  return root
end

local function surface_bucket(surface_index)
  local root = ensure_root()
  root.audio_cooldowns[surface_index] = root.audio_cooldowns[surface_index] or {}
  return root.audio_cooldowns[surface_index]
end

local function increment_counter(sound_path)
  local counters = ensure_root().audio_counters
  counters[sound_path] = (counters[sound_path] or 0) + 1
end

function audio.initialize()
  ensure_root()
end

function audio.play(surface, sound_path, position, key, cooldown_ticks)
  if not surface or not position or not sound_path or not key then
    return false
  end
  local current_tick = game.tick
  local bucket = surface_bucket(surface.index)
  if not audio_policy.can_play(bucket[key], current_tick, cooldown_ticks or 0) then
    return false
  end
  bucket[key] = current_tick
  surface.play_sound({path = sound_path, position = position})
  increment_counter(sound_path)
  return true
end

function audio.mark_flyby(record, player_index)
  record.flyby_players = record.flyby_players or {}
  if record.flyby_players[player_index] then
    return false
  end
  record.flyby_players[player_index] = true
  return true
end

function audio.update(tick)
  local root = ensure_root()
  local cutoff = tick - 36000
  for surface_index, bucket in pairs(root.audio_cooldowns) do
    for key, last_tick in pairs(bucket) do
      if last_tick < cutoff then
        bucket[key] = nil
      end
    end
    if next(bucket) == nil then
      root.audio_cooldowns[surface_index] = nil
    end
  end
end

return audio
