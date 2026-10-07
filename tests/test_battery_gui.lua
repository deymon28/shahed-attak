package.path='./?.lua;'..package.path
package.loaded['scripts.audio']={play=function() end}
package.loaded['scripts.ordnance']={}
defines={gui_type={entity=1},relative_gui_type={turret_gui=1},relative_gui_position={right=1}}
local function element(properties)
  local node=properties or {}
  node.valid=true
  node.style={}
  node.add=function(spec)
    local child=element(spec)
    node[spec.name or tostring(#node+1)]=child
    child.destroy=function() child.valid=false; node[spec.name]=nil end
    return child
  end
  return node
end
local current={}
storage={shahed_attack={surfaces={[1]=current}}}
local force={index=1}
local function battery(id)
  return {valid=true,unit_number=id,name='shahed-attack-abm-battery',force=force,surface={index=1},operable=true}
end
local first,second=battery(1),battery(2)
local players={}
for index=1,3 do
  players[index]={index=index,force=force,opened_gui_type=1,opened=index==3 and second or first,gui={relative=element()}}
end
game={players=players,get_player=function(index) return players[index] end}
local defense=require('scripts.defense')
local found=io.open('scripts/battery_gui.lua','r')
assert(found,'Opening a battery must expose its per-entity target selector')
found:close()
local gui=require('scripts.battery_gui')
local frame_name='shahed-attack-battery-mode'
local selector_name='shahed-attack-battery-mode-selection'
local function selector(index) return players[index].gui.relative[frame_name][selector_name] end
for index=1,3 do gui.on_opened({player_index=index}) end
assert(selector(1).selected_index==1 and #selector(1).items==3,'Default UI must expose three modes with ballistic-only selected')
selector(1).selected_index=2
gui.on_selection_changed({player_index=1,element=selector(1)})
assert(defense.get_mode(first)=='both' and defense.get_mode(second)=='ballistic','Changing the selector affects only the opened battery')
assert(selector(2).selected_index==2 and selector(3).selected_index==1,'Other viewers of the same battery must see the latest mode')
selector(3).selected_index=3
gui.on_selection_changed({player_index=3,element=selector(3)})
assert(defense.get_mode(second)=='drones','Third option selects drone-only')
local stale=selector(1)
players[1].opened=second
stale.selected_index=1
gui.on_selection_changed({player_index=1,element=stale})
assert(defense.get_mode(first)=='both' and defense.get_mode(second)=='drones','A stale GUI event must not change another battery')
gui.on_closed({player_index=1})
assert(not players[1].gui.relative[frame_name],'Closing the inventory removes the attached panel')
gui.on_opened({player_index=1})
assert(selector(1).selected_index==3,'Reopening reflects the stored mode')
players[1].force={index=3}
selector(1).selected_index=1
gui.on_selection_changed({player_index=1,element=selector(1)})
assert(defense.get_mode(second)=='drones','Another force cannot change battery settings')
second.valid=false
gui.update()
assert(not players[3].gui.relative[frame_name],'Destroyed batteries do not leave a usable stale panel')
print('PASS: battery GUI defaults, selection, independent batteries, multiple viewers, reopening and stale event protection')
