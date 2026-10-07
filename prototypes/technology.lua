local air_defense = table.deepcopy(data.raw.technology["military-2"])
air_defense.name = "shahed-attack-air-defense"
air_defense.localised_name = {"technology-name.shahed-attack-air-defense"}
air_defense.localised_description = {"technology-description.shahed-attack-air-defense"}
air_defense.icon = "__shahed-attack__/graphics/icons/aa-turret.png"
air_defense.icon_size = 64
air_defense.prerequisites = {"military-2", "electronics"}
air_defense.effects = {
  {type = "unlock-recipe", recipe = "shahed-attack-early-warning-radar"},
  {type = "unlock-recipe", recipe = "shahed-attack-aa-turret"},
  {type = "unlock-recipe", recipe = "shahed-attack-flak-magazine"}
}
air_defense.unit = {
  count = 100,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1}
  },
  time = 30
}

local ballistic_defense = table.deepcopy(data.raw.technology.rocketry)
ballistic_defense.name = "shahed-attack-ballistic-defense"
ballistic_defense.localised_name = {"technology-name.shahed-attack-ballistic-defense"}
ballistic_defense.localised_description = {"technology-description.shahed-attack-ballistic-defense"}
ballistic_defense.icon = "__shahed-attack__/graphics/icons/abm-battery.png"
ballistic_defense.icon_size = 64
ballistic_defense.prerequisites = {
  "shahed-attack-air-defense",
  "military-3",
  "rocketry",
  "advanced-circuit"
}
ballistic_defense.effects = {
  {type = "unlock-recipe", recipe = "shahed-attack-abm-battery"},
  {type = "unlock-recipe", recipe = "shahed-attack-interceptor"}
}
ballistic_defense.unit = {
  count = 300,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}
  },
  time = 30
}

data:extend({air_defense, ballistic_defense})
