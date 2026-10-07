local relay = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
relay.name = "shahed-attack-radar-signal-relay"
relay.hidden = true
relay.flags = {
  "placeable-off-grid",
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "not-selectable-in-game",
  "not-repairable",
  "hide-alt-info"
}
relay.minable = nil
relay.draw_circuit_wires = false
relay.draw_copper_wires = false
relay.max_health = 1
relay.collision_box = {{0, 0}, {0, 0}}
relay.selection_box = {{0, 0}, {0, 0}}
relay.collision_mask = {layers = {}}
relay.item_slot_count = 2
relay.sprites = {
  north = {filename = "__core__/graphics/empty.png", size = 1},
  east = {filename = "__core__/graphics/empty.png", size = 1},
  south = {filename = "__core__/graphics/empty.png", size = 1},
  west = {filename = "__core__/graphics/empty.png", size = 1}
}
relay.activity_led_sprites = relay.sprites
relay.activity_led_light = nil

data:extend({
  {
    type = "virtual-signal",
    name = "shahed-attack-air-raid-signal",
    icon = "__shahed-attack__/graphics/icons/strike-drone.png",
    icon_size = 64,
    subgroup = "virtual-signal-special",
    order = "z[shahed-attack]-a[air-raid]"
  },
  {
    type = "virtual-signal",
    name = "shahed-attack-ballistic-signal",
    icon = "__shahed-attack__/graphics/icons/ballistic-missile.png",
    icon_size = 64,
    subgroup = "virtual-signal-special",
    order = "z[shahed-attack]-b[ballistic]"
  },
  relay
})
