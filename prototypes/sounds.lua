local function sound(name, filename, volume)
  return {
    type = "sound",
    name = "shahed-attack-" .. name,
    filename = "__shahed-attack__/sound/" .. filename,
    volume = volume
  }
end

local sound_source = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])
sound_source.name = "shahed-attack-ballistic-sound-source"
sound_source.hidden = true
sound_source.flags = {
  "placeable-off-grid",
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "not-selectable-in-game",
  "not-repairable",
  "hide-alt-info"
}
sound_source.minable = nil
sound_source.max_health = 1
sound_source.collision_box = {{0, 0}, {0, 0}}
sound_source.selection_box = {{0, 0}, {0, 0}}
sound_source.collision_mask = {layers = {}}
sound_source.picture = {filename = "__core__/graphics/empty.png", size = 1}
sound_source.working_sound = {
  sound = {
    filename = "__shahed-attack__/sound/ballistic-flight-loop.ogg",
    volume = 0.72,
    audible_distance_modifier = 1.8
  },
  max_sounds_per_prototype = 4,
  fade_in_ticks = 6,
  fade_out_ticks = 10,
  use_doppler_shift = true
}

data:extend({
  sound("drone-flyby", "drone-flyby.ogg", 0.65),
  sound("flak-burst", "flak-burst.ogg", 0.62),
  sound("drone-impact", "drone-impact.ogg", 0.78),
  sound("heavy-impact", "heavy-impact.ogg", 0.9),
  sound("wreck-impact", "wreck-impact.ogg", 0.7),
  sound("fuel-explosion", "fuel-explosion.ogg", 0.76),
  sound("warhead-explosion", "warhead-explosion.ogg", 0.92),
  sound("ballistic-launch", "ballistic-launch.ogg", 0.9),
  sound("ballistic-impact", "ballistic-impact.ogg", 1.0),
  sound("intercept-launch", "intercept-launch.ogg", 0.8),
  sound("intercept-burst", "intercept-burst.ogg", 0.82),
  sound("radar-ping", "radar-ping.ogg", 0.40),
  sound("air-raid-siren", "air-raid-siren.ogg", 0.85),
  sound("ballistic-warning", "ballistic-warning.ogg", 0.9),
  sound_source
})
