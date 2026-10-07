local policy = {}

local VALID = {
  ["both"] = true,
  ["global-sound"] = true,
  ["circuit-only"] = true
}

function policy.normalize(mode)
  return VALID[mode] and mode or "both"
end

function policy.plays_global(mode, player_sound_enabled)
  local normalized = policy.normalize(mode)
  return player_sound_enabled == true and normalized ~= "circuit-only"
end

function policy.publishes_circuit(mode)
  return policy.normalize(mode) ~= "global-sound"
end

return policy
