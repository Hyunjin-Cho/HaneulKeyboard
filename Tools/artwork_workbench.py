"""2026-10-25: import edited ORA parts and round-trip the bind pose.

Reads the saved editor file; never re-extracts the original or overwrites a version.
Only local Pillow/OpenRaster is used. No motion authoring or product installation.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import io
import json
import os
import shutil
import tempfile
from PIL import Image
from artwork_layers import audit_ora, layer_part, ordered_parts, read_ora, png_bytes


def digest(data): return hashlib.sha256(data).hexdigest()


def import_edited_parts(ora, destination):
    ora, destination = Path(ora).resolve(), Path(destination).resolve()
    if destination.exists():
        raise FileExistsError('Use a new version directory; existing parts are never overwritten')
    source_bytes = ora.read_bytes()
    report = audit_ora(ora)
    if not report['leftBehindEveryBodyPart'] or not report['cachedPreviewMatchesLayers']:
        raise ValueError('Fix the layer order and cached preview before importing')
    root, stack, data = read_ora(ora)
    canvas = [int(root.attrib['w']), int(root.attrib['h'])]
    records = []
    references = []
    for layer in stack:
        part = layer_part(layer)
        raw = data[layer.attrib['src']]
        if layer.attrib.get('visibility', 'visible') == 'hidden':
            references.append({'name': layer.attrib['name'], 'embeddedPNG_SHA256': digest(raw)})
            continue
        if float(layer.attrib.get('opacity', '1')) != 1 or layer.attrib.get('composite-op', 'svg:src-over') != 'svg:src-over':
            raise ValueError('Unsupported opacity/blend mode')
        records.append({'part': part, 'file': part + '.png', 'sha256': digest(raw),
                        'x': int(layer.attrib.get('x', 0)), 'y': int(layer.attrib.get('y', 0)),
                        'label': layer.attrib['name'], 'archiveSource': layer.attrib['src']})
    order = ordered_parts(r['part'] for r in records)
    cached = Image.open(io.BytesIO(data['mergedimage.png'])).convert('RGBA')
    manifest = {
        'format': 1, 'createdAt': datetime.datetime.now().astimezone().isoformat(),
        'editedORA': str(ora), 'editedORA_SHA256': digest(source_bytes),
        'canvas': canvas, 'coordinateOrigin': 'top-left', 'renderOrderBackToFront': order,
        'bindRGBA_SHA256': digest(cached.tobytes()), 'parts': records, 'hiddenReferences': references,
        'status': 'editable-source round-trip; not approval of anatomy, motion or product artwork',
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.artwork-import-', dir=destination.parent))
    try:
        for record in records:
            (temporary / record['file']).write_bytes(data[record['archiveSource']])
        (temporary / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        preview = compose_bind(temporary / 'manifest.json')
        if digest(preview.tobytes()) != manifest['bindRGBA_SHA256']:
            raise ValueError('Editor-to-PNG round-trip changed the composite')
        if ora.read_bytes() != source_bytes:
            raise ValueError('The editor file changed during import; retry the saved version')
        (temporary / 'bind.png').write_bytes(png_bytes(preview))
        if destination.exists(): raise FileExistsError('Destination appeared during import')
        os.rename(temporary, destination)
    finally:
        if temporary.exists(): shutil.rmtree(temporary)
    return manifest


def compose_bind(manifest_path):
    manifest_path = Path(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('format') != 1 or manifest.get('coordinateOrigin') != 'top-left':
        raise ValueError('Unsupported parts manifest')
    records = manifest['parts']
    by_name = {r['part']: r for r in records}
    order = ordered_parts(r['part'] for r in records)
    if order != manifest['renderOrderBackToFront']:
        raise ValueError('Manifest depth differs from the shared layer policy')
    output = Image.new('RGBA', tuple(manifest['canvas']))
    for name in order:
        record = by_name[name]
        # Names are fixed part IDs; never follow a path supplied by an image filename.
        if record['file'] != name + '.png': raise ValueError('Invalid part filename')
        raw = (manifest_path.parent / record['file']).read_bytes()
        if digest(raw) != record['sha256']:
            raise ValueError('A part changed after import; import the saved editor version again')
        image = Image.open(io.BytesIO(raw)).convert('RGBA')
        x, y = record['x'], record['y']
        if x < 0 or y < 0 or x + image.width > output.width or y + image.height > output.height:
            raise ValueError('Part would be clipped; correct the editor canvas before importing')
        output.alpha_composite(image, (x, y))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    importer = commands.add_parser('import-parts')
    importer.add_argument('ora', type=Path); importer.add_argument('output', type=Path)
    preview = commands.add_parser('preview')
    preview.add_argument('manifest', type=Path); preview.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.command == 'import-parts':
        result = import_edited_parts(args.ora, args.output)
        print(f"PASS: {len(result['parts'])} parts; editor composite matches PNG round-trip")
    else:
        image = compose_bind(args.manifest)
        with args.output.open('xb') as stream: stream.write(png_bytes(image))
        print('PASS: bind preview saved without overwriting an existing file')


if __name__ == '__main__': main()
