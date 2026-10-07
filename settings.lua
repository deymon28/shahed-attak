data:extend({
  {
    type = "double-setting",
    name = "shahed-attack-raid-frequency-multiplier",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0.25,
    maximum_value = 4,
    order = "a-a"
  },
  {
    type = "double-setting",
    name = "shahed-attack-raid-size-multiplier",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0.25,
    maximum_value = 4,
    order = "a-b"
  },
  {
    type = "double-setting",
    name = "shahed-attack-damage-multiplier",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0.25,
    maximum_value = 3,
    order = "a-c"
  },
  {
    type = "double-setting",
    name = "shahed-attack-flak-accuracy",
    setting_type = "runtime-global",
    default_value = 0.62,
    minimum_value = 0.25,
    maximum_value = 0.90,
    order = "a-d"
  },
  {
    type = "bool-setting",
    name = "shahed-attack-ballistic-enabled",
    setting_type = "runtime-global",
    default_value = true,
    order = "b-a"
  },
  {
    type = "double-setting",
    name = "shahed-attack-ballistic-frequency-multiplier",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0.25,
    maximum_value = 4,
    order = "b-b"
  },
  {
    type = "double-setting",
    name = "shahed-attack-external-share",
    hidden = true,
    setting_type = "runtime-global",
    default_value = 0.15,
    minimum_value = 0,
    maximum_value = 0.5,
    order = "b-c"
  },
  {
    type = "bool-setting",
    name = "shahed-attack-recon-enabled",
    setting_type = "runtime-global",
    default_value = true,
    order = "b-d"
  },
  {
    type = "string-setting",
    name = "shahed-attack-alert-delivery",
    setting_type = "runtime-global",
    default_value = "both",
    allowed_values = {"both", "global-sound", "circuit-only"},
    order = "c-a"
  },
  {
    type = "bool-setting",
    name = "shahed-attack-alert-sound",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "d-a"
  },
  {
    type = "bool-setting",
    name = "shahed-attack-verbose-alerts",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "d-b"
  }
})


data:extend({
  {type="double-setting",name="shahed-attack-intercept-accuracy",setting_type="runtime-global",
    default_value=0.70,minimum_value=0,maximum_value=1,order="a-e"}
})
