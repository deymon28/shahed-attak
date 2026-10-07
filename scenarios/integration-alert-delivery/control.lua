local original_mode

local function restore_settings()
  if original_mode then
    remote.call("shahed_attack", "set_alert_delivery", original_mode)
  end
end

local function fail(message)
  restore_settings()
  error("SHAHED_TEST_FAIL: " .. message)
end

script.on_init(function()
  game.speed = 16
  original_mode = settings.global["shahed-attack-alert-delivery"].value

  local cases = {
    {mode = "both", personal = true, global_sound = true, circuit = true},
    {mode = "global-sound", personal = true, global_sound = true, circuit = false},
    {mode = "circuit-only", personal = true, global_sound = false, circuit = true}
  }

  for _, case in ipairs(cases) do
    local changed = remote.call("shahed_attack", "set_alert_delivery", case.mode)
    if not changed or not changed.ok then
      fail("owning mod rejected delivery mode " .. case.mode)
    end
    local delivery = remote.call("shahed_attack", "get_alert_delivery_state")
    if not delivery then
      fail("remote alert delivery state is unavailable")
    end
    if delivery.mode ~= case.mode then
      fail("delivery mode did not update to " .. case.mode)
    end
    if delivery.global_sound_enabled ~= case.global_sound then
      fail("global sound policy is incorrect for " .. case.mode)
    end
    if delivery.circuit_enabled ~= case.circuit then
      fail("circuit policy is incorrect for " .. case.mode)
    end
  end

  restore_settings()
  log("SHAHED_TEST_PASS global alert delivery modes match the tested policy")
end)
