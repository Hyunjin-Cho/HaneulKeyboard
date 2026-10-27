"""2026-10-25: cutout layer policy; near=right/front, far=left/back.

Python render order is back-to-front. OpenRaster XML is top-to-bottom.
Only ordering changes: PNG parts, canvas positions and pose geometry are retained.
Run with .tools/motion/bin/python. Local Pillow only; no network/generation.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from PIL import Image, ImageChops

PARTS_BACK_TO_FRONT = (
    'far_upper_arm', 'far_forearm', 'far_hand',
    'far_thigh', 'far_shin', 'far_sock', 'far_shoe', 'far_sole',
    'near_thigh', 'near_shin', 'near_sock', 'near_shoe', 'near_sole',
    'repair', 'garment', 'skirt_layer', 'skirt', 'body', 'body_front',
    'torso', 'head', 'ribbon',
    'near_upper_arm', 'near_forearm', 'near_hand', 'braid',
)
RANK = {name: i for i, name in enumerate(PARTS_BACK_TO_FRONT)}
LABEL_TO_PART = {
    '왼팔 위팔과 소매': 'far_upper_arm', '왼팔 아래팔과 소매': 'far_forearm', '왼손': 'far_hand',
    '오른팔 위팔과 소매': 'near_upper_arm', '오른팔 아래팔과 소매': 'near_forearm', '오른손': 'near_hand',
    '왼쪽 허벅지와 바지': 'far_thigh', '왼쪽 종아리와 버선': 'far_shin',
    '왼쪽 신발': 'far_shoe', '왼쪽 신발 밑창': 'far_sole',
    '오른쪽 허벅지와 바지': 'near_thigh', '오른쪽 종아리와 버선': 'near_shin',
    '오른쪽 신발': 'near_shoe', '오른쪽 신발 밑창': 'near_sole',
    '가려진 옷 보강': 'repair', '치마 또는 덧옷 아랫단': 'garment',
    '치마': 'skirt_layer', '기존 치마 합본': 'skirt', '기존 몸통 합본': 'body',
    '머리와 저고리와 고름': 'body_front', '저고리와 몸통': 'torso',
    '머리와 얼굴': 'head', '고름': 'ribbon', '땋은 머리와 댕기': 'braid',
}


def ordered_parts(names):
    names = list(names)
    if len(set(names)) != len(names):
        raise ValueError('Duplicate body part names')
    unknown = set(names) - RANK.keys()
    if unknown:
        raise ValueError(f'Unknown body parts: {sorted(unknown)}')
    return sorted(names, key=RANK.__getitem__)


def ordered_attachments(attachments):
    by_name = {a['name']: a for a in attachments}
    return [by_name[n] for n in ordered_parts(a['name'] for a in attachments)]


def layer_part(layer):
    name = layer.attrib['name']
    if name == '선택 원본':
        if layer.attrib.get('visibility') != 'hidden':
            raise ValueError('The full original must remain a hidden reference')
        return None
    part = LABEL_TO_PART.get(name, name)
    if part not in RANK:
        raise ValueError(f'Unknown layer {name!r}; classify it before exporting')
    return part


def read_ora(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Damaged OpenRaster archive')
        data = {name: archive.read(name) for name in archive.namelist()}
    root = ET.fromstring(data['stack.xml'])
    stack = root.find('stack')
    if stack is None or any(node.tag != 'layer' for node in stack):
        raise ValueError('Expected a flat editable parts stack')
    return root, stack, data


def composite(root, layers, data):
    canvas = Image.new('RGBA', (int(root.attrib['w']), int(root.attrib['h'])))
    for layer in reversed(layers):
        if layer.attrib.get('visibility', 'visible') == 'hidden':
            continue
        if float(layer.attrib.get('opacity', '1')) != 1 or layer.attrib.get('composite-op', 'svg:src-over') != 'svg:src-over':
            raise ValueError('Unsupported opacity/blend mode; do not flatten by guessing')
        image = Image.open(io.BytesIO(data[layer.attrib['src']])).convert('RGBA')
        canvas.alpha_composite(image, (int(layer.attrib.get('x', 0)), int(layer.attrib.get('y', 0))))
    return canvas


def png_bytes(image):
    stream = io.BytesIO(); image.save(stream, format='PNG'); return stream.getvalue()


def audit_ora(path):
    root, stack, data = read_ora(path)
    parts = [layer_part(layer) for layer in stack]
    ranks = [RANK[p] for p in parts if p is not None]
    ordered_parts(p for p in parts if p is not None)
    composed = composite(root, list(stack), data)
    cached = Image.open(io.BytesIO(data['mergedimage.png'])).convert('RGBA')
    delta = ImageChops.difference(composed, cached)
    return {
        'file': str(path), 'topToBottom': [l.attrib['name'] for l in stack],
        'leftBehindEveryBodyPart': ranks == sorted(ranks, reverse=True),
        'cachedPreviewMatchesLayers': all(hi == 0 for lo, hi in delta.getextrema()),
        'partPNGHashes': {l.attrib['name']: hashlib.sha256(data[l.attrib['src']]).hexdigest() for l in stack},
        'canvas': list(composed.size),
    }


def repair_ora(path):
    path = Path(path)
    root, stack, data = read_ora(path)
    original_layers = list(stack)
    ordered_parts(p for p in map(layer_part, original_layers) if p is not None)
    # Topmost/front layer first in ORA. References stay hidden at the bottom.
    layers = sorted(original_layers, key=lambda l: RANK.get(layer_part(l), -1), reverse=True)
    stack[:] = layers
    merged = composite(root, layers, data)
    data['stack.xml'] = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    data['mergedimage.png'] = png_bytes(merged)
    thumbnail = merged.copy(); thumbnail.thumbnail((256, 256))
    data['Thumbnails/thumbnail.png'] = png_bytes(thumbnail)
    fd, temporary = tempfile.mkstemp(dir=path.parent, suffix='.ora')
    try:
        with os.fdopen(fd, 'wb') as stream, zipfile.ZipFile(stream, 'w') as archive:
            for name, content in data.items():
                archive.writestr(name, content, compress_type=zipfile.ZIP_STORED if name == 'mimetype' else zipfile.ZIP_DEFLATED)
        report = audit_ora(temporary)
        if not report['leftBehindEveryBodyPart'] or not report['cachedPreviewMatchesLayers']:
            raise ValueError('Layer/preview verification failed')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    return audit_ora(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    reports = [audit_ora(p) for p in args.files]
    args.report.write_text(json.dumps(reports, ensure_ascii=False, indent=2) + '\n')
    good = all(r['leftBehindEveryBodyPart'] and r['cachedPreviewMatchesLayers'] for r in reports)
    print('PASS' if good else 'FAIL', ': layer order and cached composite')
    raise SystemExit(0 if good else 1)


if __name__ == '__main__': main()
