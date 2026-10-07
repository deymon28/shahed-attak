local function double(name, default, minimum, maximum, order)
  return {
    type = "double-setting",
    name = "shahed-attack-" .. name,
    setting_type = "runtime-global",
    default_value = default,
    minimum_value = minimum,
    maximum_value = maximum,
    order = order
  }
end

local function int(name, default, minimum, maximum, order)
  return {
    type = "int-setting",
    name = "shahed-attack-" .. name,
    setting_type = "runtime-global",
    default_value = default,
    minimum_value = minimum,
    maximum_value = maximum,
    order = order
  }
end

local function bool(name, default, order, setting_type)
  return {
    type = "bool-setting",
    name = "shahed-attack-" .. name,
    setting_type = setting_type or "runtime-global",
    default_value = default,
    order = order
  }
end

data:extend({
  -- Drone raids
  double("raid-frequency-multiplier", 1, 0.25, 4, "a-a"),
  double("raid-size-multiplier", 1, 0.25, 4, "a-b"),
  int("max-raid-size", 40, 2, 100, "a-c"),
  double("grace-period-days", 2, 0, 30, "a-d"),
  double("damage-multiplier", 1, 0.25, 3, "a-e"),
  bool("recon-enabled", true, "a-f"),
  bool("decoys-enabled", true, "a-g"),
  bool("defense-suppression-enabled", true, "a-h"),
  bool("adaptive-raids-enabled", true, "a-i"),
  int("max-active-drones", 200, 20, 1000, "a-j"),

  -- Ballistic strikes
  bool("ballistic-enabled", true, "b-a"),
  double("ballistic-frequency-multiplier", 1, 0.25, 4, "b-b"),
  double("ballistic-start-day", 12, 0, 200, "b-c"),
  double("ballistic-start-evolution", 0.25, 0, 1, "b-d"),
  double("ballistic-preparation-minutes", 30, 0, 600, "b-e"),
  int("max-ballistic-salvo", 8, 1, 30, "b-f"),
  double("ballistic-damage-multiplier", 1, 0.25, 3, "b-g"),

  -- Air defense
  double("flak-accuracy", 0.62, 0.25, 0.90, "c-a"),
  double("intercept-accuracy", 0.70, 0, 1, "c-b"),
  int("interceptors-per-target", 2, 1, 8, "c-c"),

  -- Warnings
  {
    type = "string-setting",
    name = "shahed-attack-alert-delivery",
    setting_type = "runtime-global",
    default_value = "both",
    allowed_values = {"both", "global-sound", "circuit-only"},
    order = "d-a"
  },
  bool("alert-sound", true, "e-a", "runtime-per-user"),
  bool("verbose-alerts", true, "e-b", "runtime-per-user"),
  bool("show-defense-ranges", true, "e-c", "runtime-per-user"),
  bool("show-radar-ranges", false, "e-d", "runtime-per-user")
})
