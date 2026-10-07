"""Render and audit genuine moving hybrid defense meshes with fixed lighting."""
from pathlib import Path
import argparse
import json
import math
import os
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/hybrid-overhaul/defense-review'
os.environ.setdefault('OPTIX_CACHE_PATH',str(OUT/'optix-cache'))
sys.path.insert(0,str(ROOT/'tools'))
import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
from hybrid_defenses import build, animate


def setup(scale,resolution):
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.device='GPU'
    pref=bpy.context.preferences.addons['cycles'].preferences
    pref.compute_device_type='OPTIX';pref.get_devices()
    for device in pref.devices: device.use=device.type=='OPTIX'
    if not any(d.use for d in pref.devices): raise RuntimeError('OptiX is required for this preview')
    scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.render.resolution_x=scene.render.resolution_y=resolution
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
    scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('Hybrid defense neutral world');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.42,.47,.53,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.50
    scene.view_settings.view_transform='AgX'
    bpy.ops.object.camera_add(location=(0,-10,12));camera=bpy.context.object
    camera.name='Production orthographic camera';camera.rotation_euler=(Vector((0,0,.7))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=scale
    scene.camera=camera
    for name,loc,power,size in [('Upper-left key',(-4,-6,10),1450,5),('Cool edge fill',(5,2,7),750,4)]:
        bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.name=name
        light.data.energy=power;light.data.size=size
        light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
    return [{'name':d.name,'type':d.type,'enabled':d.use} for d in pref.devices]


def render(path):
    bpy.context.scene.render.filepath=str(path)
    start=time.monotonic();bpy.ops.render.render(write_still=True)
    return round(time.monotonic()-start,3)


def audit(kind,result):
    scene=bpy.context.scene;points=[]
    fixed={o.name:o.matrix_world.copy() for o in result['objects'] if o.get('hybrid_part')=='base'}
    for direction in range(64):
        animate(kind,direction,direction//2,'full',result)
        for o in result['objects']:
            if o.hide_render: continue
            if o.name in fixed:
                assert all(abs(o.matrix_world[r][c]-fixed[o.name][r][c])<1e-7 for r in range(4) for c in range(4)),o.name
            points.extend(world_to_camera_view(scene,scene.camera,o.matrix_world@Vector(p)) for p in o.bound_box)
    lo=[min(p[i] for p in points) for i in (0,1)];hi=[max(p[i] for p in points) for i in (0,1)]
    if min(lo)<.025 or max(hi)>.975: raise RuntimeError('Geometry outside fixed framing: '+str((lo,hi)))
    animate(kind,0,0,'full',result)
    return {'all_64_direction_projected_bounds':[lo,hi],'fixed_base_transform_count':len(fixed),'geometry_objects':len(result['objects']),
        'assemblies':{k:([o.name for o in v] if isinstance(v,list) else v.name) for k,v in result['movers'].items()}}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--kind',nargs='+',default=['aa','abm','radar']);parser.add_argument('--pilot',action='store_true');parser.add_argument('--resolution',type=int,default=640)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    for kind in args.kind:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        result=build(kind);folder=OUT/kind;folder.mkdir(parents=True,exist_ok=True)
        devices=setup(result['ortho_scale'],args.resolution)
        info=audit(kind,result);info['devices']=devices;info['ortho_scale']=result['ortho_scale'];info['renders']=[]
        for i in range(8):
            animate(kind,i*8,i*4,'full',result)
            path=folder/f'heading-{i*45:03d}.png'
            info['renders'].append({'path':str(path.relative_to(ROOT)),'seconds':render(path)})
        if not args.pilot:
            for i in range(16):
                animate(kind,i*4,i*2,'full',result);render(folder/f'rotation-{i:02d}.png')
            if kind in ('aa','abm'):
                for phase in range(4 if kind=='aa' else 12):
                    animate(kind,24,phase,'attack' if kind=='aa' else 'launch-preview',result)
                    for o in result['objects']:
                        if o.get('hybrid_part')=='base': o.hide_render=o.hide_viewport=False
                    render(folder/f'action-{phase:02d}.png')
            else:
                for phase in range(12):
                    animate(kind,24,phase,'alert',result)
                    for o in result['objects']:
                        if o.get('hybrid_part')!='effect':o.hide_render=o.hide_viewport=False
                    render(folder/f'action-{phase:02d}.png')
        animate(kind,8,4,'full',result)
        bpy.ops.file.pack_all()
        path=ROOT/'graphics/hybrid/models'/f'{kind}.blend';path.parent.mkdir(parents=True,exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        info['packed_images']=[{'name':im.name,'packed':bool(im.packed_file)} for im in bpy.data.images if im.users and im.type=='IMAGE']
        (folder/'audit.json').write_text(json.dumps(info,indent=2),encoding='utf-8')

if __name__=='__main__':main()
