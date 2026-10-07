local function make_impact_attack(animation, effect_id)
  return {
    type = "projectile",
    range = 1.5,
    cooldown = 30,
    ammo_category = "melee",
    ammo_type = {
      target_type = "entity",
      action = {
        type = "direct",
        action_delivery = {
          type = "instant",
          target_effects = {
            {type = "script", effect_id = effect_id}
          }
        }
      }
    },
    animation = animation,
    range_mode = "bounding-box-to-bounding-box"
  }
end

local function make_drone(name, health, speed, tint, effect_id, sprite_name, sprite_size, engine_file, engine_volume)
  local unit = table.deepcopy(data.raw.unit["small-biter"])
  unit.name = name
  unit.localised_name = {"entity-name." .. name}
  unit.localised_description = {"entity-description." .. name}
  unit.icon = "__shahed-attack__/graphics/icons/" .. sprite_name .. ".png"
  unit.icon_size = 64
  unit.max_health = health
  unit.movement_speed = speed
  unit.rotation_speed = 0.04
  unit.vision_distance = 50
  unit.render_layer = "air-object"
  unit.collision_box = {{-0.55, -0.35}, {0.55, 0.35}}
  unit.selection_box = {{-0.8, -0.8}, {0.8, 0.8}}
  unit.collision_mask = {
    layers = {["shahed-attack-air-layer"] = true},
    not_colliding_with_itself = true
  }
  unit.trigger_target_mask = {"common", "shahed-attack-air"}
  unit.resistances = {
    {type = "fire", percent = 90},
    {type = "acid", percent = 90},
    {type = "explosion", percent = 10}
  }
  unit.affected_by_tiles = false
  unit.has_belt_immunity = true
  unit.absorptions_to_join_attack = nil
  unit.ai_settings = {
    destroy_when_commands_fail = false,
    allow_try_return_to_spawner = false
  }
  unit.corpse = nil
  unit.dying_explosion = nil
  unit.walking_sound = nil
  unit.working_sound = {
    sound = {
      filename = "__shahed-attack__/sound/" .. engine_file,
      volume = engine_volume or 0.34,
      audible_distance_modifier = 1.35
    },
    max_sounds_per_prototype = 4,
    fade_in_ticks = 15,
    fade_out_ticks = 20,
    use_doppler_shift = true
  }
  unit.water_reflection = nil
  unit.map_color = tint
  unit.run_animation = {
    layers = {
      {
        filename = "__shahed-attack__/graphics/entity/" .. sprite_name .. "-sheet.png",
        priority = "high",
        width = sprite_size,
        height = sprite_size,
        direction_count = 16,
        line_length = 16,
        frame_count = 8,
        animation_speed = 0.28
      },
      {
        filename = "__shahed-attack__/graphics/entity/" .. sprite_name .. "-shadow-sheet.png",
        priority = "high",
        width = sprite_size,
        height = sprite_size,
        direction_count = 16,
        line_length = 16,
        frame_count = 8,
        animation_speed = 0.28,
        -- The source render captures airframe shape; this offset conveys flight altitude.
        shift = {1.25, 0.75},
        rotate_shift = false,
        draw_as_shadow = true
      }
    }
  }
  unit.attack_parameters = make_impact_attack(unit.run_animation, effect_id)
  return unit
end

local scout = make_drone(
  "shahed-attack-recon-drone",
  90,
  0.11,
  {r = 0.35, g = 0.8, b = 0.95, a = 1},
  "shahed-attack-scout-contact",
  "recon-drone",
  72,
  "drone-recon-loop.ogg",
  0.40
)
local strike = make_drone(
  "shahed-attack-strike-drone",
  180,
  0.08,
  {r = 0.9, g = 0.55, b = 0.15, a = 1},
  "shahed-attack-strike-impact",
  "strike-drone",
  80,
  "drone-strike-loop.ogg",
  0.50
)
local heavy = make_drone(
  "shahed-attack-heavy-drone",
  400,
  0.06,
  {r = 0.75, g = 0.1, b = 0.08, a = 1},
  "shahed-attack-heavy-impact",
  "heavy-drone",
  96,
  "drone-heavy-loop.ogg",
  0.62
)

local function make_source(name, health, sprite_name, sound_file)
  local source = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])
  source.name = name
  source.localised_name = {"entity-name." .. name}
  source.localised_description = {"entity-description." .. name}
  source.icon = "__shahed-attack__/graphics/icons/" .. sprite_name .. ".png"
  source.icon_size = 64
  source.hidden = false
  source.flags = {"placeable-enemy", "not-repairable"}
  source.minable = nil
  source.max_health = health
  source.collision_box = {{-2.4, -2.4}, {2.4, 2.4}}
  source.selection_box = {{-2.8, -2.8}, {2.8, 2.8}}
  source.map_generator_bounding_box = {{-3, -3}, {3, 3}}
  source.is_military_target = true
  source.enemy_map_color = {r = 0.95, g = 0.2, b = 0.05, a = 1}
  source.picture = {
    layers = {
      {
        filename = "__shahed-attack__/graphics/entity/" .. sprite_name .. "-base.png",
        priority = "high",
        width = 320,
        height = 320,
        scale = 0.5
      },
      {
        filename = "__shahed-attack__/graphics/entity/" .. sprite_name .. "-shadow.png",
        priority = "high",
        width = 640,
        height = 320,
        scale = 0.5,
        draw_as_shadow = true
      }
    }
  }
  source.working_sound = {
    sound = {
      filename = "__shahed-attack__/sound/" .. sound_file,
      volume = 0.42,
      audible_distance_modifier = 1.1
    },
    max_sounds_per_prototype = 2,
    fade_in_ticks = 30,
    fade_out_ticks = 45
  }
  return source
end

local airfield = make_source(
  "shahed-attack-airfield",
  1500,
  "airfield",
  "airfield-machinery-loop.ogg"
)
local ballistic_site = make_source(
  "shahed-attack-ballistic-site",
  3000,
  "ballistic-site",
  "ballistic-site-machinery-loop.ogg"
)

data:extend({scout, strike, heavy, airfield, ballistic_site})
