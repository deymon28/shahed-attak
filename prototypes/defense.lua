local function make_item(name, icon, place_result, stack_size)
  return {
    type = "item",
    name = name,
    icon = icon,
    subgroup = "defensive-structure",
    order = "z[shahed-attack]-" .. name,
    place_result = place_result,
    stack_size = stack_size or 20
  }
end

local function prepared_head(filename, size, scale)
  local body = {
    filename = filename,
    priority = "high",
    width = size,
    height = size,
    direction_count = 64,
    line_length = 8,
    frame_count = 1,
    scale = scale
  }
  local shadow = table.deepcopy(body)
  shadow.filename = filename:gsub("%.png$", "-shadow.png")
  shadow.width = size * 2
  shadow.draw_as_shadow = true
  return {layers = {body, shadow}}
end

local function attacking_head(filename, size, scale)
  local body = {
    filename = filename,
    priority = "high",
    width = size,
    height = size,
    direction_count = 64,
    line_length = 16,
    frame_count = 4,
    animation_speed = 0.5,
    scale = scale
  }
  local shadow = table.deepcopy(body)
  shadow.filename = filename:gsub("%.png$", "-shadow.png")
  shadow.width = size * 2
  shadow.draw_as_shadow = true
  return {layers = {body, shadow}}
end

local function custom_graphics_set(stem, size, scale)
  return {
    base_visualisation = {
      animation = {
        layers = {
          {
            filename = "__shahed-attack__/graphics/entity/" .. stem .. "-base.png",
            priority = "high",
            width = size,
            height = size,
            scale = scale
          },
          {
            filename = "__shahed-attack__/graphics/entity/" .. stem .. "-base-shadow.png",
            priority = "high",
            width = size * 2,
            height = size,
            scale = scale,
            draw_as_shadow = true
          }
        }
      }
    }
  }
end

local radar = table.deepcopy(data.raw.radar.radar)
radar.name = "shahed-attack-early-warning-radar"
radar.localised_name = {"entity-name.shahed-attack-early-warning-radar"}
radar.localised_description = {"entity-description.shahed-attack-early-warning-radar"}
radar.icon = "__shahed-attack__/graphics/icons/early-warning-radar.png"
radar.icon_size = 64
radar.minable.result = radar.name
radar.max_health = 500
radar.energy_usage = "1.5MW"
radar.energy_per_sector = "25MJ"
radar.energy_per_nearby_scan = "500kJ"
radar.integration_patch = nil
radar.circuit_connector = {points={
  wire={red={-0.45,0.3},green={-0.35,0.3}},
  shadow={red={-0.2,0.5},green={-0.1,0.5}}
}}
radar.pictures = {
  layers = {
    {
      filename = "__shahed-attack__/graphics/entity/early-warning-radar-sheet.png",
      priority = "high",
      width = 192,
      height = 192,
      direction_count = 32,
      line_length = 8,
      apply_projection = false,
      scale = 0.65
    },
    {
      filename = "__shahed-attack__/graphics/entity/early-warning-radar-shadow-sheet.png",
      priority = "high",
      width = 384,
      height = 192,
      direction_count = 32,
      line_length = 8,
      apply_projection = false,
      scale = 0.65,
      draw_as_shadow = true
    }
  }
}
radar.working_sound = {
  sound = {
    filename = "__shahed-attack__/sound/radar-hum-loop.ogg",
    volume = 0.38,
    audible_distance_modifier = 1.05
  },
  max_sounds_per_prototype = 2,
  fade_in_ticks = 30,
  fade_out_ticks = 45
}

local aa_turret = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
aa_turret.name = "shahed-attack-aa-turret"
aa_turret.localised_name = {"entity-name.shahed-attack-aa-turret"}
aa_turret.localised_description = {"entity-description.shahed-attack-aa-turret"}
aa_turret.icon = "__shahed-attack__/graphics/icons/aa-turret.png"
aa_turret.icon_size = 64
aa_turret.minable.result = aa_turret.name
aa_turret.max_health = 550
aa_turret.rotation_speed = 0.03
aa_turret.attack_target_mask = {"shahed-attack-air"}
aa_turret.attack_parameters.ammo_category = "shahed-attack-flak"
aa_turret.attack_parameters.range = 36
aa_turret.attack_parameters.cooldown = 24
aa_turret.attack_parameters.sound = {
  filename = "__shahed-attack__/sound/flak-shot.ogg",
  volume = 0.48,
  min_speed = 0.97,
  max_speed = 1.03
}
aa_turret.call_for_help_radius = 50
aa_turret.folded_animation_is_stateless = true
aa_turret.folded_animation = prepared_head(
  "__shahed-attack__/graphics/entity/aa-turret-head-prepared.png", 160, 0.62)
aa_turret.preparing_animation = prepared_head(
  "__shahed-attack__/graphics/entity/aa-turret-head-prepared.png", 160, 0.62)
aa_turret.prepared_animation = prepared_head(
  "__shahed-attack__/graphics/entity/aa-turret-head-prepared.png", 160, 0.62)
aa_turret.attacking_animation = attacking_head(
  "__shahed-attack__/graphics/entity/aa-turret-head-attacking.png", 160, 0.62)
aa_turret.folding_animation = prepared_head(
  "__shahed-attack__/graphics/entity/aa-turret-head-prepared.png", 160, 0.62)
aa_turret.graphics_set = custom_graphics_set("aa-turret", 160, 0.62)
aa_turret.preparing_sound = nil
aa_turret.folding_sound = nil

local abm = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
abm.name = "shahed-attack-abm-battery"
abm.localised_name = {"entity-name.shahed-attack-abm-battery"}
abm.localised_description = {"entity-description.shahed-attack-abm-battery"}
abm.icon = "__shahed-attack__/graphics/icons/abm-battery.png"
abm.icon_size = 64
abm.minable.result = abm.name
abm.max_health = 750
abm.attack_target_mask = {"shahed-attack-ballistic"}
abm.attack_parameters.ammo_category = "shahed-attack-interceptor"
abm.attack_parameters.range = 192
abm.attack_parameters.cooldown = 3600
abm.energy_source = {
  type = "electric",
  usage_priority = "secondary-input",
  buffer_capacity = "20MJ",
  input_flow_limit = "12MW",
  drain = "100kW"
}
abm.energy_per_shot = "10MJ"
abm.folded_animation_is_stateless = true
abm.folded_animation = prepared_head(
  "__shahed-attack__/graphics/entity/abm-battery-head-prepared.png", 192, 0.65)
abm.preparing_animation = prepared_head(
  "__shahed-attack__/graphics/entity/abm-battery-head-prepared.png", 192, 0.65)
abm.prepared_animation = prepared_head(
  "__shahed-attack__/graphics/entity/abm-battery-head-prepared.png", 192, 0.65)
abm.attacking_animation = prepared_head(
  "__shahed-attack__/graphics/entity/abm-battery-head-prepared.png", 192, 0.65)
abm.folding_animation = prepared_head(
  "__shahed-attack__/graphics/entity/abm-battery-head-prepared.png", 192, 0.65)
abm.graphics_set = custom_graphics_set("abm-battery", 192, 0.65)
abm.preparing_sound = nil
abm.folding_sound = nil

local flak_ammo = {
  type = "ammo",
  name = "shahed-attack-flak-magazine",
  icon = "__shahed-attack__/graphics/icons/flak-magazine.png",
  icon_size = 64,
  ammo_category = "shahed-attack-flak",
  ammo_type = {
    target_type = "entity",
    action = {
      type = "direct",
      action_delivery = {
        type = "instant",
        source_effects = {
          {type = "create-explosion", entity_name = "explosion-gunshot"}
        },
        target_effects = {
          {type = "script", effect_id = "shahed-attack-flak-shot"}
        }
      }
    }
  },
  magazine_size = 10,
  subgroup = "ammo",
  order = "z[shahed-attack]-a[flak]",
  stack_size = 100
}

local interceptor = {
  type = "ammo",
  name = "shahed-attack-interceptor",
  icon = "__shahed-attack__/graphics/icons/interceptor.png",
  icon_size = 64,
  ammo_category = "shahed-attack-interceptor",
  ammo_type = {
    target_type = "entity",
    action = {
      type = "direct",
      action_delivery = {
        type = "instant",
        target_effects = {
          {type = "create-entity", entity_name = "explosion"}
        }
      }
    }
  },
  magazine_size = 1,
  subgroup = "ammo",
  order = "z[shahed-attack]-b[interceptor]",
  stack_size = 20
}

data:extend({
  radar,
  aa_turret,
  abm,
  make_item(radar.name, radar.icon, radar.name, 20),
  make_item(aa_turret.name, aa_turret.icon, aa_turret.name, 20),
  make_item(abm.name, abm.icon, abm.name, 10),
  flak_ammo,
  interceptor,
  {
    type = "recipe",
    name = radar.name,
    enabled = false,
    ingredients = {
      {type = "item", name = "radar", amount = 1},
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 20}
    },
    results = {{type = "item", name = radar.name, amount = 1}}
  },
  {
    type = "recipe",
    name = aa_turret.name,
    enabled = false,
    ingredients = {
      {type = "item", name = "gun-turret", amount = 1},
      {type = "item", name = "engine-unit", amount = 10},
      {type = "item", name = "steel-plate", amount = 20},
      {type = "item", name = "electronic-circuit", amount = 20}
    },
    results = {{type = "item", name = aa_turret.name, amount = 1}}
  },
  {
    type = "recipe",
    name = flak_ammo.name,
    enabled = false,
    ingredients = {
      {type = "item", name = "piercing-rounds-magazine", amount = 2},
      {type = "item", name = "steel-plate", amount = 1},
      {type = "item", name = "explosives", amount = 1}
    },
    results = {{type = "item", name = flak_ammo.name, amount = 1}}
  },
  {
    type = "recipe",
    name = abm.name,
    enabled = false,
    energy_required = 20,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 50},
      {type = "item", name = "concrete", amount = 50},
      {type = "item", name = "electric-engine-unit", amount = 20},
      {type = "item", name = "advanced-circuit", amount = 40},
      {type = "item", name = "radar", amount = 2}
    },
    results = {{type = "item", name = abm.name, amount = 1}}
  },
  {
    type = "recipe",
    name = interceptor.name,
    enabled = false,
    energy_required = 12,
    ingredients = {
      {type = "item", name = "explosive-rocket", amount = 2},
      {type = "item", name = "processing-unit", amount = 5},
      {type = "item", name = "explosives", amount = 10},
      {type = "item", name = "low-density-structure", amount = 5}
    },
    results = {{type = "item", name = interceptor.name, amount = 1}}
  }
})
