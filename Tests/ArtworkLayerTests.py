"""Layer ordering regression: real ORAs plus an intentionally reversed overlap."""
from pathlib import Path
import io
import importlib.util
import json
import hashlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'Tools'))
from artwork_layers import audit_ora, repair_ora, ordered_parts, ordered_attachments
from artwork_workbench import import_edited_parts, compose_bind


class ArtworkLayerTests(unittest.TestCase):
    def test_full_reextract_is_blocked_by_default(self):
        folder = REPO / 'Review/2026-10-25-three-person-recovery'
        before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*_부품.ora')}
        process = subprocess.run([sys.executable, str(folder / 'build_recovery.py')],
                                 capture_output=True, text=True, timeout=20)
        self.assertEqual(process.returncode, 2)
        self.assertIn('import-parts', process.stderr)
        self.assertEqual(before, {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in before})

    def test_renderer_ignores_wrong_attachment_construction_order(self):
        path = REPO / 'Review/2026-10-25-three-person-recovery/build_recovery.py'
        spec = importlib.util.spec_from_file_location('checked_recovery_renderer', path)
        renderer = importlib.util.module_from_spec(spec); spec.loader.exec_module(renderer)
        parts = {}
        for name, color in [('garment', 'blue'), ('far_forearm', 'red')]:
            image = Image.new('RGBA', (1254, 1254))
            ImageDraw.Draw(image).rectangle((300, 500, 400, 600), fill=color)
            parts[name] = image
        pose = {'attachments': [dict(name=name, sourcePivot=(0, 0), pivot=(0, 0), angle=0)
                                for name in ['garment', 'far_forearm']]}
        result = renderer.render(pose, parts)
        self.assertEqual(result.getpixel((430, 640)), (0, 0, 255, 255))

    def test_wrong_order_really_covers_body_then_repair_preserves_parts(self):
        # XML starts with the frontmost layer: the red far arm wrongly hides blue body.
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'counterexample.ora'
            root = ET.Element('image', w='2', h='2', version='0.0.3')
            stack = ET.SubElement(root, 'stack')
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('mimetype', 'image/openraster')
                for name, file, color in [
                    ('왼팔 아래팔과 소매', 'arm.png', 'red'),
                    ('치마 또는 덧옷 아랫단', 'body.png', 'blue'),
                ]:
                    ET.SubElement(stack, 'layer', name=name, src=file, x='0', y='0',
                                  opacity='1.0', visibility='visible', **{'composite-op': 'svg:src-over'})
                    data = io.BytesIO(); Image.new('RGBA', (2, 2), color).save(data, format='PNG')
                    archive.writestr(file, data.getvalue())
                data = io.BytesIO(); Image.new('RGBA', (2, 2), 'red').save(data, format='PNG')
                archive.writestr('mergedimage.png', data.getvalue())
                archive.writestr('stack.xml', ET.tostring(root))
            before = audit_ora(path)
            self.assertFalse(before['leftBehindEveryBodyPart'])
            self.assertTrue(before['cachedPreviewMatchesLayers'])
            after = repair_ora(path)
            self.assertTrue(after['leftBehindEveryBodyPart'])
            self.assertTrue(after['cachedPreviewMatchesLayers'])
            self.assertEqual(before['partPNGHashes'], after['partPNGHashes'])
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(Image.open(io.BytesIO(archive.read('mergedimage.png'))).getpixel((0, 0)), (0, 0, 255, 255))

    def test_unclassified_or_duplicate_parts_fail(self):
        for names in [['head', 'head'], ['head', 'new_unclassified_sleeve']]:
            with self.assertRaises(ValueError): ordered_parts(names)

    def test_geometry_survives_all_existing_poses(self):
        path = REPO / 'Review/2026-10-25-three-person-recovery/motion.json'
        count = 0
        for person in json.loads(path.read_text())['people'].values():
            for pose in person['poses']:
                original = {a['name']: a for a in pose['attachments']}
                fixed = ordered_attachments(pose['attachments'])
                self.assertEqual(original, {a['name']: a for a in fixed})
                count += 1
        self.assertEqual(count, 21)

    def test_editable_character_files_match_depth_and_preview(self):
        files = sorted((REPO / 'Review/2026-10-25-three-person-recovery').glob('*_부품.ora'))
        self.assertEqual(len(files), 3)
        for path in files:
            with self.subTest(character=path.name):
                report = audit_ora(path)
                self.assertTrue(report['leftBehindEveryBodyPart'])
                self.assertTrue(report['cachedPreviewMatchesLayers'])

    def test_editor_import_roundtrip_is_exact_and_preserves_versions(self):
        files = sorted((REPO / 'Review/2026-10-25-three-person-recovery').glob('*_부품.ora'))
        with tempfile.TemporaryDirectory() as directory:
            for index, source in enumerate(files):
                with self.subTest(character=source.name):
                    destination = Path(directory) / str(index)
                    imported = import_edited_parts(source, destination)
                    result = compose_bind(destination / 'manifest.json')
                    with zipfile.ZipFile(source) as archive:
                        original = Image.open(io.BytesIO(archive.read('mergedimage.png'))).convert('RGBA')
                    self.assertEqual(original.tobytes(), result.tobytes())
                    with self.assertRaises(FileExistsError): import_edited_parts(source, destination)
                    record = imported['parts'][0]
                    part = destination / record['file']
                    part.write_bytes(part.read_bytes() + b'changed')
                    with self.assertRaises(ValueError): compose_bind(destination / 'manifest.json')


if __name__ == '__main__': unittest.main()
