local audio_policy = {}

function audio_policy.can_play(last_tick, current_tick, cooldown)
  return last_tick == nil or current_tick - last_tick >= cooldown
end

return audio_policy
