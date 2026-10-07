local collision_mask_util = require("collision-mask-util")
require("prototypes.ground_defense")

for _, projectile in pairs(data.raw.projectile or {}) do
  local mask = projectile.hit_collision_mask
  if not mask then
    mask = table.deepcopy(collision_mask_util.get_default_mask("projectile/hit"))
    projectile.hit_collision_mask = mask
  end
  mask.layers = mask.layers or {}
  mask.layers["shahed-attack-air-layer"] = true
end
