-- Add new combat state without replacing live threats or their original flight timing.
local root = storage.shahed_attack
if not root then return end
root.schema_version = 5
root.source_inspected = root.source_inspected or {}
for _, current in pairs(root.surfaces or {}) do
  current.projectiles = current.projectiles or {}
  current.battery_next_shot = current.battery_next_shot or {}
  current.combat_rng_state = current.combat_rng_state or current.rng_state
  current.warning_history = current.warning_history or {}
  current.ballistic_readiness = current.ballistic_readiness or {}
  for _, drone in pairs(current.active_drones or {}) do
    if drone.source and drone.source.valid then drone.source_unit_number = drone.source.unit_number end
  end
end
