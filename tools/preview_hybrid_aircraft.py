"""Render and assemble aircraft closeups, eight views, motion and scale reviews."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/hybrid-overhaul/aircraft-review'
os.environ['OPTIX_CACHE_PATH']=str(OUT/'optix-cache')
sys.path.insert(0, str(ROOT / 'tools'))


def assemble():
    from PIL import Image, ImageDraw
    kinds = ('recon', 'strike', 'heavy', 'wreck', 'ballistic-missile', 'interceptor', 'flak-round', 'flak-magazine')
    game = {'recon':72,'strike':80,'heavy':96,'wreck':80,'ballistic-missile':128,'interceptor':128,'flak-round':32,'flak-magazine':64}
    validations = {}
    for kind in kinds:
        folder = OUT / kind
        files = sorted(folder.glob('view-*.png'))
        if not files:
            continue
        sheet = Image.new('RGB', (1024, 2*300), '#303733')
        draw = ImageDraw.Draw(sheet)
        for index, path in enumerate(files[:8]):
            im = Image.open(path).convert('RGBA')
            im.thumbnail((248,248), Image.Resampling.LANCZOS)
            x, y = index%4*256, index//4*300
            sheet.paste(im, (x+(256-im.width)//2,y+22), im)
            draw.text((x+8,y+7),path.stem,fill='#eef0e1')
        sheet.save(folder/'views-contact.png')
        scale = Image.new('RGB',(640,160),'#52594b')
        d = ImageDraw.Draw(scale)
        for index,path in enumerate(files[:4]):
            im = Image.open(path).convert('RGBA').resize((game[kind],game[kind]), Image.Resampling.LANCZOS)
            x=index*160+(160-game[kind])//2
            scale.paste(im,(x,25),im)
            d.text((index*160+12,140),f'{kind} {game[kind]} px',fill='white')
        scale.save(folder/'game-scale.png')
        frames=[]
        hashes=[]
        for path in sorted(folder.glob('motion-*.png')):
            im = Image.open(path).convert('RGBA')
            hashes.append(hashlib.sha256(im.tobytes()).hexdigest())
            bg=Image.new('RGBA',im.size,'#303733')
            bg.alpha_composite(im)
            frames.append(bg.convert('RGB').resize((384,384),Image.Resampling.LANCZOS))
        if frames:
            frames[0].save(folder/'motion.gif',save_all=True,append_images=frames[1:],duration=120,loop=0)
        bounds={}
        for path in sorted(folder.glob('view-*.png'))+sorted(folder.glob('motion-*.png'))+[folder/'shadow.png']:
            im=Image.open(path).convert('RGBA')
            box=im.getchannel('A').getbbox()
            bounds[path.name]={'bbox':box,'edge_padding':min(box[0],box[1],im.width-box[2],im.height-box[3]) if box else None}
        validations[kind]={'renders':bounds,'motion_frame_count':len(hashes),'unique_motion_frames':len(set(hashes))}
    (OUT/'png-validation.json').write_text(json.dumps(validations,indent=2),encoding='utf-8')
    selections={
        'ballistic-missile':{'source':'graphics/source/ballistic-missile.png','rotate_ccw_degrees':0,'size':128},
        'interceptor':{'source':'graphics/source/interceptor.png','rotate_ccw_degrees':45,'size':128},
        'flak-magazine':{'source':'graphics/source/flak-magazine.png','rotate_ccw_degrees':0,'size':64},
        'flak-round':{'source':'build/hybrid-overhaul/aircraft-review/flak-round/retained-tracer.png','rotate_ccw_degrees':0,'size':32},
    }
    selected_sheet=Image.new('RGB',(640,220),'#52594b')
    sd=ImageDraw.Draw(selected_sheet)
    for index,(kind,selection) in enumerate(selections.items()):
        im=Image.open(ROOT/selection['source']).convert('RGBA')
        if selection['rotate_ccw_degrees']:
            im=im.rotate(selection['rotate_ccw_degrees'],resample=Image.Resampling.BICUBIC,expand=True)
        if kind!='flak-round':
            im=im.crop(im.getchannel('A').getbbox())
            im.thumbnail((selection['size']-12,selection['size']-12),Image.Resampling.LANCZOS)
        x=index*160+(160-im.width)//2
        selected_sheet.paste(im,(x,24),im)
        sd.text((index*160+8,170),kind,fill='white')
        sd.text((index*160+8,188),f"{selection['size']} px / retained",fill='white')
    selected_sheet.save(OUT/'selected-static-review.png')
    (OUT/'production-static-selections.json').write_text(json.dumps(selections,indent=2),encoding='utf-8')


def render_all(args):
    import bpy
    import numpy as np
    from bpy_extras.object_utils import world_to_camera_view
    from mathutils import Vector
    import hybrid_aircraft as aircraft
    import hybrid_renderer as renderer
    kinds = args.kinds.split(',')
    validation_path=OUT/'scene-validation.json'
    report=json.loads(validation_path.read_text(encoding='utf-8')) if validation_path.exists() else {}
    for kind in kinds:
        scene=renderer.setup(640,7.7,32 if args.pilot else 48)
        result=aircraft.build(kind)
        scene.camera.data.ortho_scale=result['ortho_scale']
        folder=OUT/kind
        folder.mkdir(parents=True,exist_ok=True)
        directions=8 if kind=='wreck' else 16
        phases=12 if kind=='wreck' else 8
        is_air=kind in ('recon','strike','heavy','wreck')
        camera_matrix=tuple(v for row in scene.camera.matrix_world for v in row)
        # Sample the actual geometry, including extrema; rotated cuboid bounds
        # unnecessarily shrink delta wings and long, thin recon wings.
        records=[]
        for obj in result['objects']:
            if obj.type=='MESH':
                points=np.empty(len(obj.data.vertices)*3,dtype=np.float32)
                obj.data.vertices.foreach_get('co',points)
                points=points.reshape(-1,3)
                indices=list(range(0,len(points),max(1,len(points)//3000)))
                indices.extend(np.argmin(points,axis=0))
                indices.extend(np.argmax(points,axis=0))
                points=points[indices]
            else:
                points=np.array(obj.bound_box,dtype=np.float32)
            records.append((obj,points))
        limits=[1.,1.,0.,0.]
        camera_inverse=np.array(scene.camera.matrix_world.inverted(),dtype=np.float32)
        for direction in range(directions if is_air else 1):
            for phase in range(phases if is_air else 1):
                aircraft.animate(kind,direction,phase,'wreck' if kind=='wreck' else 'flight',result)
                for obj,points in records:
                    matrix=np.array(obj.matrix_world,dtype=np.float32)
                    world=points@matrix[:3,:3].T+matrix[:3,3]
                    shadow=world.copy()
                    shadow[:,:2]-=world[:,2,None]*np.array((renderer.SUN.x/renderer.SUN.z,renderer.SUN.y/renderer.SUN.z))
                    shadow[:,2]=.005
                    for vertices in (world,shadow):
                        view=vertices@camera_inverse[:3,:3].T+camera_inverse[:3,3]
                        uv=view[:,:2]/scene.camera.data.ortho_scale+.5
                        limits=[min(limits[0],float(uv[:,0].min())),min(limits[1],float(uv[:,1].min())),max(limits[2],float(uv[:,0].max())),max(limits[3],float(uv[:,1].max()))]
        # Leave at least 5% padding for conservative bounds, without camera movement.
        reach=max(.5-limits[0],.5-limits[1],limits[2]-.5,limits[3]-.5)
        if reach>.45:
            result['ortho_scale']*=reach/.45
            scene.camera.data.ortho_scale=result['ortho_scale']
        aircraft.animate(kind,0,0,'flight',result)
        scene.render.image_settings.color_depth='8'
        if args.audit_only:
            packed=[{'name':image.name,'packed':bool(image.packed_file)} for image in bpy.data.images if image.source=='FILE' and image.users]
            report[kind]={'objects':len(result['objects']),'faces':sum(len(o.data.polygons) for o in result['objects'] if o.type=='MESH'),
                         'ortho_scale':result['ortho_scale'],'all_pose_sampled_bounds':limits,'source':result.get('source'),
                         'movers':list(result['movers']),'camera_fixed':camera_matrix==tuple(v for row in scene.camera.matrix_world for v in row)}
            validation_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
            print('AIRCRAFT_POSE_AUDIT',kind,json.dumps(report[kind]),flush=True)
            continue
        renderer.pack_scene(ROOT/'graphics/hybrid/models'/f'{kind}.blend')
        views=(0,2,4,6,8,10,12,14) if is_air and kind!='wreck' else ((0,1,2,3,4,5,6,7) if kind=='wreck' else (0,))
        if args.pilot:
            views=views[:1]
        if args.motion_only:
            views=()
        for direction in views:
            aircraft.animate(kind,direction,0,'flight',result)
            renderer.render(folder/f'view-{direction:02d}.png')
        if not args.pilot and is_air:
            for phase in range(phases):
                aircraft.animate(kind,2,phase,'wreck' if kind=='wreck' else 'flight',result)
                renderer.render(folder/f'motion-{phase:02d}.png')
        aircraft.animate(kind,2 if is_air else 0,0,'flight',result)
        shadow=renderer.ShadowPass(result['objects'])
        shadow.render(folder/'shadow.png',result['objects'])
        packed=[{'name':image.name,'packed':bool(image.packed_file)} for image in bpy.data.images if image.source=='FILE' and image.users]
        report[kind]={'objects':len(result['objects']),'faces':sum(len(o.data.polygons) for o in result['objects'] if o.type=='MESH'),
                      'ortho_scale':result['ortho_scale'],'pre_fit_conservative_bounds':limits,'source':result.get('source'),
                      'movers':list(result['movers']),'images':packed,'camera_fixed':camera_matrix==tuple(v for row in scene.camera.matrix_world for v in row)}
        (OUT/'scene-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('AIRCRAFT_REVIEW',kind,json.dumps(report[kind]),flush=True)


def verify_packed(args):
    import bpy
    result={}
    for kind in args.kinds.split(','):
        path=ROOT/'graphics/hybrid/models'/f'{kind}.blend'
        bpy.ops.wm.open_mainfile(filepath=str(path))
        scene=bpy.context.scene
        images=[{'name':im.name,'packed':bool(im.packed_file)} for im in bpy.data.images if im.source=='FILE' and im.users]
        meshes=[o for o in scene.objects if o.type=='MESH']
        result[kind]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
                      'images':images,'all_used_images_packed':all(i['packed'] for i in images),
                      'camera_location':list(scene.camera.location),'ortho_scale':scene.camera.data.ortho_scale,
                      'source_meshes':[{'name':o.name,'uv_layers':[uv.name for uv in o.data.uv_layers],
                                        'color_attributes':[c.name for c in o.data.color_attributes]} for o in meshes if o.get('source')]}
        assert result[kind]['all_used_images_packed'],kind
    (OUT/'packed-scene-validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('PACKED_AIRCRAFT_VERIFIED',','.join(result),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--assemble',action='store_true')
    parser.add_argument('--pilot',action='store_true')
    parser.add_argument('--audit-only',action='store_true')
    parser.add_argument('--motion-only',action='store_true')
    parser.add_argument('--verify-packed',action='store_true')
    parser.add_argument('--kinds',default='recon,strike,heavy,wreck,ballistic-missile,interceptor,flak-round,flak-magazine')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    OUT.mkdir(parents=True,exist_ok=True)
    assemble() if args.assemble else (verify_packed(args) if args.verify_packed else render_all(args))
