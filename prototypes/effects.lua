local function outcome_action(outcome)
  local definitions = {
    safe = {
      entity = "small-scorchmark-tintable",
      sound = "wreck-impact.ogg",
      volume = 0.65
    },
    fuel = {
      entity = "explosion",
      sound = "fuel-explosion.ogg",
      volume = 0.8,
      radius = 2.5,
      damage = 30
    },
    warhead = {
      entity = "big-explosion",
      sound = "warhead-explosion.ogg",
      volume = 0.95,
      radius = 4,
      damage = 110
    }
  }
  local definition = definitions[outcome]
  local effects = {
    {type = "create-entity", entity_name = definition.entity},
    {
      type = "play-sound",
      sound = {
        filename = "__shahed-attack__/sound/" .. definition.sound,
        volume = definition.volume
      }
    }
  }
  if definition.damage then
    effects[#effects + 1] = {
      type = "nested-result",
      action = {
        type = "area",
        radius = definition.radius,
        action_delivery = {
          type = "instant",
          target_effects = {
            {type = "damage", damage = {amount = definition.damage, type = "explosion"}}
          }
        }
      }
    }
  end
  effects[#effects + 1] = {
    type = "script",
    effect_id = "shahed-attack-wreck-completed-" .. outcome
  }
  return {
    type = "direct",
    action_delivery = {
      type = "instant",
      target_effects = effects
    }
  }
end

local function make_falling_wreck(outcome, direction, recon)
  local projectile = table.deepcopy(data.raw.projectile.grenade)
  local prefix = recon and "falling-recon-wreck" or "falling-wreck"
  projectile.name = "shahed-attack-" .. prefix .. "-" .. outcome .. "-" .. direction
  projectile.hidden = true
  projectile.action = outcome_action(outcome)
  projectile.light = {intensity = 0.25, size = 2}
  projectile.acceleration = 0
  -- A positional target must remain authoritative so the projectile impacts.
  -- direction_only would use the target merely as a heading and fly forever.
  projectile.direction_only = false
  projectile.rotatable = false
  projectile.animation = {
    filename = "__shahed-attack__/graphics/entity/" .. prefix .. "-" .. direction .. ".png",
    priority = "high",
    width = 96,
    height = 96,
    frame_count = 12,
    line_length = 12,
    animation_speed = 12 / 90,
    scale = 0.85
  }
  projectile.shadow = {
    filename = "__shahed-attack__/graphics/entity/" .. prefix .. "-shadow-" .. direction .. ".png",
    priority = "high",
    width = 96,
    height = 96,
    frame_count = 12,
    line_length = 12,
    animation_speed = 12 / 90,
    scale = 0.85,
    draw_as_shadow = true
  }
  projectile.smoke = nil
  return projectile
end

local prototypes = {}
for _, outcome in ipairs({"safe", "fuel", "warhead"}) do
  for direction = 0, 7 do
    prototypes[#prototypes + 1] = make_falling_wreck(outcome, direction)
    prototypes[#prototypes + 1] = make_falling_wreck(outcome, direction, true)
  end
end

data:extend(prototypes)
