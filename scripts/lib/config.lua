-- Single access point for mod settings.
-- Boolean settings must be read with an explicit nil check: the old
-- `value and value.value or fallback` idiom turned every disabled toggle
-- back into its default `true`.
local config = {}

config.DEFAULTS = {
  ["shahed-attack-raid-frequency-multiplier"] = 1,
  ["shahed-attack-raid-size-multiplier"] = 1,
  ["shahed-attack-max-raid-size"] = 40,
  ["shahed-attack-grace-period-days"] = 2,
  ["shahed-attack-damage-multiplier"] = 1,
  ["shahed-attack-flak-accuracy"] = 0.62,
  ["shahed-attack-intercept-accuracy"] = 0.70,
  ["shahed-attack-interceptors-per-target"] = 2,
  ["shahed-attack-ballistic-enabled"] = true,
  ["shahed-attack-ballistic-frequency-multiplier"] = 1,
  ["shahed-attack-ballistic-start-day"] = 12,
  ["shahed-attack-ballistic-start-evolution"] = 0.25,
  ["shahed-attack-ballistic-preparation-minutes"] = 30,
  ["shahed-attack-max-ballistic-salvo"] = 8,
  ["shahed-attack-ballistic-damage-multiplier"] = 1,
  ["shahed-attack-recon-enabled"] = true,
  ["shahed-attack-decoys-enabled"] = true,
  ["shahed-attack-defense-suppression-enabled"] = true,
  ["shahed-attack-adaptive-raids-enabled"] = true,
  ["shahed-attack-max-active-drones"] = 200,
  ["shahed-attack-alert-delivery"] = "both",
  ["shahed-attack-alert-sound"] = true,
  ["shahed-attack-verbose-alerts"] = true,
  ["shahed-attack-show-defense-ranges"] = true,
  ["shahed-attack-show-radar-ranges"] = false
}

local function resolve(entry, name, fallback)
  if entry ~= nil and entry.value ~= nil then
    return entry.value
  end
  if fallback ~= nil then
    return fallback
  end
  return config.DEFAULTS[name]
end

function config.global(name, fallback)
  return resolve(settings.global[name], name, fallback)
end

function config.player(player, name, fallback)
  if not player or not player.valid then
    return resolve(nil, name, fallback)
  end
  local player_settings = settings.get_player_settings(player)
  return resolve(player_settings and player_settings[name], name, fallback)
end

return config
