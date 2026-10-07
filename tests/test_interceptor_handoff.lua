local h = require("tests.lib.harness")
h.reset()
local smoke = 0
local surface = h.nauvis
surface.create_trivial_smoke = function() smoke = smoke + 1 end
game.tick = 100
local current = h.surface_state()
local function render(args) return h.render(args) end
local ordnance = require('scripts.ordnance')
local battery = h.entity({name='shahed-attack-abm-battery', position={x=10,y=20}, orientation=.25})
local missile = {id=1, position={x=1010,y=20}, force_index=1}
current.active_missiles[1] = missile
local shot = ordnance.launch_interceptor(current, battery, missile, 1, 'm1')
assert(not shot.render.visible and not shot.light.visible,
  'The launch animation must own the rocket before it clears the container')
assert(shot.launch_render.args.animation_speed==0 and shot.launch_render.args.animation_offset==0,
  'The launch frame must be driven by projectile age rather than an independent render clock')
for tick=100,113 do
  game.tick=tick;ordnance.update(tick)
  assert(not shot.render.visible, 'Do not duplicate the rocket during the launch animation')
end
assert(smoke==0 and not missile.intercepted, 'No flight trail or encounter inside the launcher')
assert(shot.launch_render.animation_offset==7, 'The last body frame must match the hidden projectile pose')
game.tick=114;ordnance.update(game.tick)
assert(shot.render.visible and shot.light.visible, 'The flight body appears at the animation handoff')
assert(shot.launch_render.animation_offset==8, 'The launch animation must be body-free at handoff')
-- Independently measured from the east-facing 3D launch frame using its camera.
assert(math.abs(shot.position.x-11.126283044)<.00001 and math.abs(shot.position.y-18.911841714)<.00001,
  'The flight body must start at the exiting rocket, not above the turret center')
assert(shot.render.x_scale>.25 and shot.render.x_scale<.30, 'Match the exiting model size before scaling to flight')
local previous={x=shot.position.x,y=shot.position.y}
game.tick=115;ordnance.update(game.tick)
local dx,dy=shot.position.x-previous.x,shot.position.y-previous.y
assert(math.abs(math.sqrt(dx*dx+dy*dy)-.72)<.00001, 'Acceleration starts after the handoff without a position jump')
game.tick=126;ordnance.update(game.tick)
assert(shot.render.x_scale==1, 'The flight body reaches its normal scale smoothly')

-- Losing a target while the body still belongs to the animation removes both.
game.tick=200
local cancelled=ordnance.launch_interceptor(current,battery,missile,1,'m1')
missile.finished=true
for tick=201,240 do game.tick=tick;ordnance.update(tick) end
assert(not cancelled.render.valid and not cancelled.light.valid and not cancelled.launch_render.valid,
  'A cancelled launch must not leave a phantom rocket in the animation')
assert(not current.projectiles[cancelled.id], 'Cancelled projectile state is removed')
missile.finished=false
local legacy={id=99,kind='abm',start_tick=280,position={x=10,y=20},origin={x=0,y=20},
  destination=missile.position,target_missile_id=1,accuracy=1,
  render=render({target={x=10,y=20}}),light=render({target={x=10,y=20}})}
current.projectiles[99]=legacy;game.tick=300;ordnance.update(game.tick)
assert(legacy.render.visible and math.abs(legacy.position.x-16)<.00001,
  'An older saved projectile without launch fields must continue its existing flight')
print('PASS: single rocket, calibrated launch anchor, continuous handoff, gentle flight and cancellation cleanup')
