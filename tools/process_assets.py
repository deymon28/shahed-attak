"""Pack verified Blender renders without rotating or fabricating source PNGs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

try:
    from tools.asset_manifest import ALPHA_THRESHOLD, RUNTIME_ASSETS, RuntimeAsset, asset
    from tools.hybrid_manifest import render_plan, fingerprint
    from tools.check_render_quality import failures
    from tools.structure_shadow_assets import KINDS as STRUCTURE_KINDS, pack as pack_structure_shadows
except ModuleNotFoundError:  # Direct execution from tools/.
    from asset_manifest import ALPHA_THRESHOLD, RUNTIME_ASSETS, RuntimeAsset, asset
    from hybrid_manifest import render_plan, fingerprint
    from check_render_quality import failures
    from structure_shadow_assets import KINDS as STRUCTURE_KINDS, pack as pack_structure_shadows


RESAMPLING = Image.Resampling.LANCZOS


def threshold_alpha(image: Image.Image, threshold: int = ALPHA_THRESHOLD) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 0 if value < threshold else value)
    rgba.putalpha(alpha)
    return rgba


def alpha_crop(image: Image.Image, threshold: int = ALPHA_THRESHOLD) -> Image.Image:
    rgba = threshold_alpha(image, threshold)
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("Source image has no pixels at or above the alpha threshold")
    return rgba.crop(bbox)


def resize_premultiplied(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize without leaking hidden RGB into transparent edge pixels."""
    premultiplied = image.convert("RGBa")
    resized = premultiplied.resize(size, RESAMPLING)
    return threshold_alpha(resized.convert("RGBA"))


def fit(
    image: Image.Image,
    size: tuple[int, int],
    margin: int,
    threshold: int = ALPHA_THRESHOLD,
) -> Image.Image:
    available = (size[0] - margin * 2, size[1] - margin * 2)
    if available[0] <= 0 or available[1] <= 0:
        raise ValueError("Margin leaves no drawable area")
    source = alpha_crop(image, threshold)
    scale = min(available[0] / source.width, available[1] / source.height)
    resized = resize_premultiplied(
        source,
        (max(1, round(source.width * scale)), max(1, round(source.height * scale))),
    )
    canvas = Image.new("RGBA", size)
    offset = ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2)
    canvas.alpha_composite(resized, offset)
    return threshold_alpha(canvas, threshold)


def assert_clear_edges(
    image: Image.Image,
    cell_size: tuple[int, int],
    columns: int,
    threshold: int = ALPHA_THRESHOLD,
) -> None:
    rgba = image.convert("RGBA")
    width, height = cell_size
    if rgba.width % width or rgba.height % height:
        raise ValueError("sheet dimensions are not divisible by the declared cell size")
    cells = (rgba.width // width) * (rgba.height // height)
    for index in range(cells):
        x = index % columns * width
        y = index // columns * height
        if x + width > rgba.width or y + height > rgba.height:
            break
        alpha = rgba.crop((x, y, x + width, y + height)).getchannel("A")
        edges = (
            alpha.crop((0, 0, width, 1)),
            alpha.crop((0, height - 1, width, height)),
            alpha.crop((0, 0, 1, height)),
            alpha.crop((width - 1, 0, width, height)),
        )
        if any(any(value >= threshold for value in edge.getdata()) for edge in edges):
            raise ValueError(f"cell {index} touches its edge")


def _validate_cells(image: Image.Image, record: RuntimeAsset) -> None:
    try:
        assert_clear_edges(image, record.cell_size, record.columns)
    except ValueError as exc:
        raise ValueError(f'{record.path}: {exc}') from exc
    hashes: set[str] = set()
    for index in range(record.directions * record.frames):
        x = index % record.columns * record.cell_size[0]
        y = index // record.columns * record.cell_size[1]
        cell = image.crop((x, y, x + record.cell_size[0], y + record.cell_size[1]))
        if cell.getchannel("A").getbbox() is None:
            raise ValueError(f"{record.path}: blank cell {index}")
        digest = hashlib.sha256(cell.tobytes()).hexdigest()
        if not record.allow_static_duplicates and digest in hashes:
            raise ValueError(f"{record.path}: duplicate cell {index}")
        hashes.add(digest)


def _save(image: Image.Image, output: Path, record: RuntimeAsset) -> None:
    image = threshold_alpha(image)
    if image.size != record.sheet_size:
        raise ValueError(f"{record.path}: expected {record.sheet_size}, got {image.size}")
    _validate_cells(image, record)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, optimize=True)


def render_shadow(polygons: list, size: int) -> Image.Image:
    """Rasterize Blender's geometric cast-shadow faces at 4x resolution."""
    large = size * 4
    alpha = Image.new('L', (large, large))
    draw = ImageDraw.Draw(alpha)
    for poly in polygons:
        draw.polygon([(round(x*large), round(y*large)) for x,y in poly], fill=95)
    rgba = Image.new('RGBA', alpha.size, (12, 15, 18, 0))
    rgba.putalpha(alpha)
    return resize_premultiplied(rgba, (size, size))


def cell(sheet: Image.Image, record: RuntimeAsset, index: int) -> Image.Image:
    w,h=record.cell_size
    x,y=index%record.columns*w,index//record.columns*h
    return sheet.crop((x,y,x+w,y+h))


def place(sheet: Image.Image, frame: Image.Image, record: RuntimeAsset, index: int):
    sheet.alpha_composite(frame,(index%record.columns*record.cell_size[0],index//record.columns*record.cell_size[1]))


def icon_source(root: Path, name: str) -> Image.Image:
    folder=root/'graphics/renders'
    plan = next(p for p in render_plan() if p['name'] == 'icon-' + name)
    if plan['method'] == 'retained-2d':
        return retained_image(root, plan)
    return Image.open(folder/('icon-'+name)/'0000.png').convert('RGBA')


def retained_image(root: Path, plan: dict) -> Image.Image:
    """Explicit static ordnance art, never an animated-geometry fallback."""
    if plan['kind'] not in ('ballistic-missile', 'interceptor', 'flak-magazine', 'flak-round') or plan['directions'] * plan['frames'] != 1:
        raise ValueError('Retained 2D artwork is restricted to approved static ordnance')
    with Image.open(root / plan['retained_source']) as source:
        image = source.convert('RGBA')
    if plan['source_rotation']:
        image = image.rotate(plan['source_rotation'], Image.Resampling.BICUBIC, expand=True)
    return image


def write_contact_sheets(root: Path, destination: Path) -> None:
    destination.mkdir(parents=True,exist_ok=True)
    overview=Image.new('RGB',(1200,960),(42,46,40))
    overview_draw=ImageDraw.Draw(overview)
    names=['aa-turret','abm-battery','early-warning-radar','recon-drone','strike-drone','heavy-drone','airfield','ballistic-site','ballistic-missile','interceptor','flak-magazine']
    for i,name in enumerate(names):
        icon=fit(icon_source(root,name),(260,260),20)
        x,y=i%4*300,i//4*320
        overview.paste(icon,(x+20,y+30),icon)
        overview_draw.text((x+15,y+12),name,fill='white')
    overview.save(destination/'blender-overview.png')
    for name in ('aa-turret','abm-battery','early-warning-radar','recon-drone','strike-drone','heavy-drone','airfield','ballistic-site'):
        if name in ('aa-turret','abm-battery'):
            rec=asset(f'graphics/entity/{name}-head-prepared.png')
            base=Image.open(root/f'graphics/entity/{name}-base.png').convert('RGBA')
            indices=list(range(0,64,4))
        else:
            file=f'{name}-overlay-sheet.png' if name in ('airfield','ballistic-site') else f'{name}-sheet.png'
            rec=asset('graphics/entity/'+file)
            base=Image.open(root/f'graphics/entity/{name}-base.png').convert('RGBA') if name in ('airfield','ballistic-site') else None
            indices=list(range(0,rec.directions*rec.frames,max(1,rec.directions*rec.frames//16)))[:16]
        sheet=Image.open(root/rec.path).convert('RGBA')
        preview=Image.new('RGB',(1024,1088),(42,46,40));draw=ImageDraw.Draw(preview)
        animated=[]
        for i,index in enumerate(indices):
            frame=cell(sheet,rec,index)
            if base is not None:
                composite=base.copy();composite.alpha_composite(frame);frame=composite
            if name in ('aa-turret','abm-battery'):
                shadow_record=asset(f'graphics/entity/{name}-head-prepared-shadow.png')
                head_shadows=Image.open(root/shadow_record.path).convert('RGBA')
                ground=Image.open(root/f'graphics/entity/{name}-base-shadow.png').convert('RGBA')
                ground.alpha_composite(cell(head_shadows,shadow_record,index))
                ground.putalpha(ground.getchannel('A').point(lambda value: round(value * .55)))
                ground.alpha_composite(frame, ((ground.width-frame.width)//2, 0));frame=ground
            preview_size=(248, round(248*frame.height/frame.width))
            scaled=resize_premultiplied(frame,preview_size)
            frame=Image.new('RGBA',(248,248))
            frame.alpha_composite(scaled,(0,(248-scaled.height)//2))
            x,y=i%4*256,i//4*272
            preview.paste(frame,(x+4,y+22),frame)
            draw.text((x+8,y+5),f'{name} frame {index}',fill='white')
            gif=Image.new('RGB',(248,248),(42,46,40));gif.paste(frame,(0,0),frame);animated.append(gif)
        preview.save(destination/(name+'-contact.png'))
        animated[0].save(destination/(name+'-turntable.gif'),save_all=True,append_images=animated[1:],duration=130,loop=0)
    actions=[
        ('aa-firing','aa-turret-head-attacking',list(range(32,36)),'aa-turret-base'),
        ('abm-launch','abm-battery-launch-sheet',list(range(12)),'abm-battery-base'),
        ('ballistic-launch','ballistic-site-launch-sheet',list(range(20)),'ballistic-site-base'),
        ('falling-wreck','falling-wreck-1',list(range(12)),None),
    ]
    for title,name,indices,base_name in actions:
        rec=asset(f'graphics/entity/{name}.png')
        sheet=Image.open(root/rec.path).convert('RGBA')
        base=Image.open(root/f'graphics/entity/{base_name}.png').convert('RGBA') if base_name else None
        if title=='abm-launch':
            head_rec=asset('graphics/entity/abm-battery-head-prepared.png')
            heads=Image.open(root/head_rec.path).convert('RGBA')
            base.alpha_composite(cell(heads,head_rec,0))
        preview=Image.new('RGB',(1024,272*((len(indices)+3)//4)),(42,46,40))
        draw=ImageDraw.Draw(preview);frames=[]
        for i,index in enumerate(indices):
            frame=cell(sheet,rec,index)
            if base:
                bg=base.copy();bg.alpha_composite(frame);frame=bg
            frame=resize_premultiplied(frame,(248,248))
            x,y=i%4*256,i//4*272
            preview.paste(frame,(x+4,y+22),frame)
            draw.text((x+8,y+5),f'{title} phase {i}',fill='white')
            gif=Image.new('RGB',(248,248),(42,46,40));gif.paste(frame,(0,0),frame);frames.append(gif)
        preview.save(destination/(title+'-contact.png'))
        frames[0].save(destination/(title+'.gif'),save_all=True,append_images=frames[1:],duration=100,loop=0)


def pack(root: Path) -> None:
    if failures(root):
        raise ValueError('Black-material render failure; run python -m tools.check_render_quality --repair')
    render_root=root/'graphics/renders'
    plan_path=render_root/'plan.json'
    if not plan_path.exists():
        raise FileNotFoundError('Blender render cache missing. Run tools/render_assets.ps1 first; flat PNG rotation is not supported.')
    plans=json.loads(plan_path.read_text())
    if plans != render_plan():
        raise ValueError('Render plan does not match current hybrid production contracts')
    source_hashes = {kind: fingerprint(kind, root) for kind in {p['kind'] for p in plans}}
    for plan in plans:
        source_hash = source_hashes[plan['kind']]
        icon=plan['name'].startswith('icon-')
        target=('graphics/icons/'+plan['name'][5:] if icon else 'graphics/entity/'+plan['name'])+'.png'
        record=asset(target)
        sheet=Image.new('RGBA',record.sheet_size)
        shadow_record=asset('graphics/entity/'+plan['shadow']+'.png') if plan['shadow'] and plan['kind'] not in STRUCTURE_KINDS else None
        shadow_sheet=Image.new('RGBA',shadow_record.sheet_size) if shadow_record else None
        if plan['method'] == 'retained-2d':
            frame = fit(retained_image(root, plan), record.cell_size, 3 if icon else 4)
            _save(frame, root / record.path, record)
            print(f'Packed retained artwork {record.path}', flush=True)
            continue
        for index in range(plan['directions']*plan['frames']):
            path=render_root/plan['name']/f'{index:04d}.png'
            if not path.exists():
                raise FileNotFoundError(f'Missing Blender frame {path}. Resume tools/render_assets.ps1; old art is never substituted.')
            stamp=path.with_suffix('.source.sha256')
            if not stamp.exists() or stamp.read_text()!=source_hash:
                raise ValueError(f'Stale Blender frame {path}; run tools/render_assets.ps1 to rebuild from the current geometry.')
            with Image.open(path) as opened:
                frame=fit(icon_source(root,plan['name'][5:]),record.cell_size,3) if icon else resize_premultiplied(opened.convert('RGBA'),record.cell_size)
            place(sheet,frame,record,index)
            if shadow_record:
                with Image.open(path.with_suffix('.shadow.png')) as opened_shadow:
                    shadow = opened_shadow.convert('RGBA')
                shadow.putalpha(shadow.getchannel('A').point(lambda value: round(value * 95 / 255)))
                place(shadow_sheet,resize_premultiplied(shadow, record.cell_size),shadow_record,index)
        _save(sheet,root/record.path,record)
        if shadow_record: _save(shadow_sheet,root/shadow_record.path,shadow_record)
        print(f'Packed {record.path}',flush=True)
    pack_recon_wreck(root)
    pack_structure_shadows(root)
    (render_root / 'geometry.json').write_text((render_root / 'hybrid-geometry.json').read_text())


def pack_recon_wreck(root: Path) -> None:
    try:
        from tools.recon_wreck_assets import validate_sources
    except ModuleNotFoundError:
        from recon_wreck_assets import validate_sources
    validate_sources(root)
    for direction in range(8):
        for suffix in ('', '-shadow'):
            record = asset(f'graphics/entity/falling-recon-wreck{suffix}-{direction}.png')
            sheet = Image.new('RGBA', record.sheet_size)
            for phase in range(12):
                path = root / 'graphics/renders' / f'falling-recon-wreck-{direction}' / f'{phase:04d}{".shadow" if suffix else ""}.png'
                with Image.open(path) as opened:
                    frame = opened.convert('RGBA')
                if suffix:
                    frame.putalpha(frame.getchannel('A').point(lambda value: round(value * 95 / 255)))
                place(sheet, resize_premultiplied(frame, record.cell_size), record, phase)
            _save(sheet, root / record.path, record)


def main() -> None:
    parser=argparse.ArgumentParser(description='Pack reproducible Blender renders into Factorio runtime sheets.')
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--contact-sheets',type=Path)
    parser.add_argument('--validate-only',action='store_true')
    args=parser.parse_args()
    root=args.root.resolve()
    if not args.validate_only: pack(root)
    for record in RUNTIME_ASSETS:
        with Image.open(root/record.path) as opened:
            image=opened.convert('RGBA')
        if image.size!=record.sheet_size: raise ValueError(f'Incorrect dimensions: {record.path}')
        _validate_cells(image,record)
    if args.contact_sheets:
        write_contact_sheets(root,args.contact_sheets if args.contact_sheets.is_absolute() else root/args.contact_sheets)
    print(f'Validated {len(RUNTIME_ASSETS)} Blender runtime assets.')


if __name__=='__main__': main()


