package.path='./?.lua;'..package.path
local launches=0
package.loaded['scripts.ordnance']={launch_interceptor=function() launches=launches+1 end}
package.loaded['scripts.alerts']={}
package.loaded['scripts.audio']={play=function() end}
package.loaded['scripts.visual_effects']={play_abm_launch=function() end}
defines={inventory={turret_ammo=1},entity_status_diode={green=1,yellow=2,red=3}}
settings={global={}}
game={tick=0}
local defense=require('scripts.defense')
local surface={defenses={abm_batteries={}},battery_next_shot={},counters={},active_missiles={}}
for i=1,5 do
 local inventory={count=10}
 inventory.get_item_count=function() return inventory.count end
 inventory.remove=function() inventory.count=inventory.count-1;return 1 end
 surface.defenses.abm_batteries[i]={valid=true,unit_number=i,position={x=0,y=0},orientation=0,
  force={index=1},energy=40000000,get_inventory=function() return inventory end}
end
local missile={id=1,force_index=1,position={x=100,y=0},probabilities={}}
surface.active_missiles[1]=missile
assert(not defense.try_intercepts(missile,surface))
assert(launches==0,'ready batteries must aim briefly before firing')
local previous=0
local first_launch
for tick=1,30 do
 game.tick=tick;defense.try_intercepts(missile,surface)
 local heading=surface.defenses.abm_batteries[1].orientation
 assert(heading>=previous and heading-previous<=1/60+0.000001,'turret turns smoothly toward target')
 previous=heading
 if launches>0 then first_launch=tick;break end
end
assert(first_launch and first_launch>=15 and first_launch<=30,'quarter-turn acquisition is slower but remains bounded')
assert(launches==5,'every ready aimed battery launches')
game.tick=first_launch+59;defense.try_intercepts(missile,surface)
assert(launches==5,'no launch before reload')
game.tick=first_launch+60;defense.try_intercepts(missile,surface)
assert(launches==10,'tracking persists through the original one-second reload')
for _,battery in ipairs(surface.defenses.abm_batteries) do
 assert(battery.energy==20000000 and battery.get_inventory().count==8,'charge resources only for actual launches')
end
game.tick=first_launch+120;missile.position={x=193,y=0};defense.try_intercepts(missile,surface)
assert(launches==10,'no launch outside finite radius')
missile.position={x=0,y=0}
for tick=game.tick+1,game.tick+30 do game.tick=tick;defense.try_intercepts(missile,surface);if launches==15 then break end end
assert(launches==15,'close targets remain interceptable after reacquisition')
missile.intercepted=true;game.tick=game.tick+60
assert(defense.try_intercepts(missile,surface) and launches==15,'stop shooting destroyed missiles')
print('PASS: smooth bounded acquisition, all ready batteries, reload, range, and resource accounting')
