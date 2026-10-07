package.path='./?.lua;'..package.path
local created
local surface={index=1,create_entity=function(args) created=args;return {} end}
local surface_state={active_drones={},rng_state=1234}
package.loaded['scripts.state']={get_surface=function() return surface_state end}
package.loaded['scripts.forces']={get=function() return {} end}
package.loaded['scripts.audio']={}
package.loaded['scripts.alerts']={}
game={forces={enemy={get_evolution_factor=function() return 0 end}}}
local raids=require('scripts.raids')
local drone={unit_number=1,surface=surface,position={x=10,y=0},orientation=.25}
surface_state.active_drones[1]={kind='recon',last_motion={x=1,y=0}}
raids.on_entity_died({entity=drone})
assert(created and created.name:find('falling-recon-wreck',1,true),'Recon must fall with its own airframe')
assert(surface_state.active_drones[1]==nil,'Death removes the tracked drone exactly once')
surface_state.active_drones[1]={kind='strike',last_motion={x=1,y=0}}
raids.on_entity_died({entity=drone})
assert(created.name:find('falling-wreck-',1,true),'Strike wreck keeps its existing appearance')
print('PASS: recon wreck keeps its aircraft family')
