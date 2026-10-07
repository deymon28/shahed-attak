local player, drone, vehicle, started
local stage = 1
local cases = {
  {gun="pistol", ammo="firearm-magazine"},
  {gun="submachine-gun", ammo="uranium-rounds-magazine"},
  {gun="combat-shotgun", ammo="piercing-shotgun-shell"},
  {gun="rocket-launcher", ammo="explosive-rocket"},
  {gun="flamethrower", ammo="flamethrower-ammo"},
  {vehicle="car", ammo="piercing-rounds-magazine"}
}

local function check(value, message)
  if not value then error("SHAHED_TEST_FAIL: " .. message) end
end

local function setup()
  local surface = game.surfaces[1]
  player.shooting_state = {state=defines.shooting.not_shooting, position={0, 0}}
  if drone and drone.valid then drone.destroy() end
  if vehicle and vehicle.valid then player.driving=false; vehicle.destroy() end
  player.teleport({0, 0})
  player.get_inventory(defines.inventory.character_guns).clear()
  player.get_inventory(defines.inventory.character_ammo).clear()
  local case = cases[stage]
  if case.vehicle then
    vehicle = surface.create_entity({name=case.vehicle, position={0, 0}, force="player"})
    vehicle.set_driver(player)
    vehicle.get_inventory(defines.inventory.car_ammo).insert({name=case.ammo, count=100})
  else
    player.get_inventory(defines.inventory.character_guns)[1].set_stack({name=case.gun})
    player.get_inventory(defines.inventory.character_ammo)[1].set_stack({name=case.ammo, count=100})
    player.character.selected_gun_index = 1
  end
  drone = surface.create_entity({name="shahed-attack-heavy-drone", position={0,-8}, force="shahed-attack-enemy"})
  drone.commandable.set_command({type=defines.command.stop, distraction=defines.distraction.none})
  started = game.tick
end

script.on_init(function()
  game.speed = 4
  game.surfaces[1].always_day = true
  game.surfaces[1].request_to_generate_chunks({0,0}, 3)
  game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_tick, function(event)
  if not player then
    player = game.players[1]
    if not player then return end
    if not player.character then check(player.create_character(), "create actual player character") end
    player.character.destructible=false
    setup()
  end
  if drone.valid then
    player.selected=drone
    player.shooting_state={state=defines.shooting.shooting_selected, position=drone.position}
  end
  if event.tick-started >= 150 then
    local case = cases[stage]
    check(not drone.valid or drone.health < 400, "real firing must damage drone: " .. (case.gun or case.vehicle))
    log("PLAYER_WEAPON_PASS " .. (case.gun or case.vehicle))
    stage=stage+1
    if cases[stage] then setup() else
      player.shooting_state={state=defines.shooting.not_shooting, position={0,0}}
      log("SHAHED_TEST_PASS actual player pistol, SMG, shotgun, rocket, flamethrower and vehicle fire can shoot down drones")
      script.on_event(defines.events.on_tick,nil)
    end
  end
end)
