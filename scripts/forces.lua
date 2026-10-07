local forces = {}

forces.name = "shahed-attack-enemy"

local function set_allied(left, right, allied)
  left.set_friend(right, allied)
  left.set_cease_fire(right, allied)
end

function forces.configure_relations(other_force)
  local air_force = game.forces[forces.name]
  if not air_force or not other_force or other_force == air_force then
    return
  end
  local allied = other_force.name == "enemy" or other_force.name == "neutral"
  set_allied(air_force, other_force, allied)
  set_allied(other_force, air_force, allied)
end

function forces.get()
  local air_force = game.forces[forces.name]
  if air_force then
    return air_force
  end
  air_force = game.create_force(forces.name)
  for _, other_force in pairs(game.forces) do
    forces.configure_relations(other_force)
  end
  return air_force
end

local function migrate_entities(air_force)
  local names = {
    "shahed-attack-recon-drone",
    "shahed-attack-strike-drone",
    "shahed-attack-heavy-drone",
    "shahed-attack-decoy-drone",
    "shahed-attack-airfield",
    "shahed-attack-ballistic-site"
  }
  for _, surface in pairs(game.surfaces) do
    for _, entity in ipairs(surface.find_entities_filtered({name = names})) do
      if entity.valid and entity.force ~= air_force then
        entity.force = air_force
      end
    end
  end
end

function forces.initialize()
  local air_force = forces.get()
  for _, other_force in pairs(game.forces) do
    forces.configure_relations(other_force)
  end
  migrate_entities(air_force)
  return air_force
end

return forces
