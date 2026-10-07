-- Turret-specific damage families preserve player ammunition and splash damage.
local ground_types = {}
for name in pairs(data.raw['damage-type']) do
  if not name:find('^shahed%-attack%-ground%-') then
    ground_types[name] = 'shahed-attack-ground-' .. name
  end
end
for _, name in pairs(ground_types) do data:extend({{type='damage-type',name=name}}) end

-- Preserve each target's vanilla resistances to these equivalent damage types.
for _, group in pairs(data.raw) do
  for _, prototype in pairs(group) do
    if prototype.resistances then
      local copies = {}
      for _, resistance in ipairs(prototype.resistances) do
        if ground_types[resistance.type] then
          local copy = table.deepcopy(resistance)
          copy.type = ground_types[resistance.type]
          copies[#copies+1] = copy
        end
      end
      for _, copy in ipairs(copies) do prototype.resistances[#prototype.resistances+1]=copy end
    end
  end
end
for _, name in ipairs({'recon','strike','heavy','decoy'}) do
  local drone = data.raw.unit['shahed-attack-'..name..'-drone']
  local kept = {}
  for _, resistance in ipairs(drone.resistances) do
    if not resistance.type:find('^shahed%-attack%-ground%-') then kept[#kept+1]=resistance end
  end
  for _, ground in pairs(ground_types) do kept[#kept+1]={type=ground,percent=100} end
  drone.resistances = kept
end

local copies = {}
local rewrite
local function clone(kind, name)
  if not data.raw[kind] or not data.raw[kind][name] then return name end
  local key = kind..'/'..name
  if copies[key] then return copies[key] end
  local new_name = 'shahed-attack-ground-'..name
  copies[key]=new_name
  local prototype=table.deepcopy(data.raw[kind][name])
  prototype.name=new_name
  rewrite(prototype)
  data:extend({prototype})
  return new_name
end

rewrite = function(node)
  if type(node) ~= 'table' then return end
  -- DamagePrototype occurs in effects, fire, beams, and stickers.
  if node.amount and ground_types[node.type] then node.type=ground_types[node.type] end
  if node.damage_type and ground_types[node.damage_type] then node.damage_type=ground_types[node.damage_type] end
  if node.type == 'projectile' and node.projectile then node.projectile=clone('projectile',node.projectile) end
  if node.type == 'artillery' and node.projectile then node.projectile=clone('artillery-projectile',node.projectile) end
  if node.type == 'stream' and node.stream then node.stream=clone('stream',node.stream) end
  if node.type == 'beam' and node.beam then node.beam=clone('beam',node.beam) end
  if node.type == 'create-sticker' and node.sticker then node.sticker=clone('sticker',node.sticker) end
  if (node.type == 'create-fire' or node.type == 'create-entity') and node.entity_name then
    if data.raw.fire[node.entity_name] then node.entity_name=clone('fire',node.entity_name) end
  end
  if node.spread_fire_entity then node.spread_fire_entity=clone('fire',node.spread_fire_entity) end
  if node.spawn_entity and data.raw.fire[node.spawn_entity] then
    node.spawn_entity=clone('fire',node.spawn_entity)
  end
  for _, child in pairs(node) do if type(child)=='table' then rewrite(child) end end
end

-- Every ground turret (vanilla or from other mods) ignores aircraft, and its
-- damage is moved to the ground-only families so splash cannot hit drones.
local TURRET_TYPES = {"ammo-turret", "electric-turret", "fluid-turret"}
local turret_categories = {["artillery-shell"] = true}

local function add_categories(parameters)
  if not parameters then return end
  if parameters.ammo_category then turret_categories[parameters.ammo_category] = true end
  for _, category in ipairs(parameters.ammo_categories or {}) do turret_categories[category] = true end
end

for _, turret_type in ipairs(TURRET_TYPES) do
  for name, turret in pairs(data.raw[turret_type] or {}) do
    if not name:find("^shahed%-attack%-") then
      turret.ignore_target_mask = turret.ignore_target_mask or {}
      table.insert(turret.ignore_target_mask, "shahed-attack-air")
      if turret_type == "ammo-turret" then add_categories(turret.attack_parameters) end
      rewrite(turret.attack_parameters)
    end
  end
end

-- Ammunition fired by those turrets gets a turret-only variant with ground
-- damage; the variant used by players and vehicles stays unchanged.
for _, ammo in pairs(data.raw.ammo) do
  if turret_categories[ammo.ammo_category] and ammo.ammo_type then
    local original = table.deepcopy(ammo.ammo_type)
    if original[1] then
      local found = false
      for _, variant in ipairs(original) do
        if variant.source_type == "turret" then rewrite(variant); found = true end
      end
      if not found then
        local turret = table.deepcopy(original[1])
        turret.source_type = "turret"
        rewrite(turret)
        original[#original + 1] = turret
      end
      ammo.ammo_type = original
    else
      original.source_type = "default"
      local turret = table.deepcopy(original)
      turret.source_type = "turret"
      rewrite(turret)
      ammo.ammo_type = {original, turret}
    end
  end
end
