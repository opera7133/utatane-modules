import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from catalog import modules, sha256
from ci_packages import GROUPS, group_for, input_key, package_name, reuse


class PackageCacheTests(unittest.TestCase):
    def test_all_binary_modules_have_one_group(self):
        entries = [entry for entry in modules() if entry['delivery'] == 'binary']
        self.assertEqual(len(entries), 20)
        self.assertEqual(group_for(next(e for e in entries if e['id'] == 'kawari')), 'native')
        self.assertEqual({group_for(entry) for entry in entries}, set(GROUPS))
        self.assertTrue(all(group_for(entry) == 'native' for entry in entries if entry['origin'] == 'native'))

    def test_input_changes_invalidate_only_relevant_packages(self):
        entry = next(entry for entry in modules() if entry['id'] == 'minato')
        tracked = ['sources/minato/src/lib.rs', 'sources/pasta/src/lib.rs', 'scripts/ci_packages.py']
        hashes = {}
        def checksum(path):
            return hashes.get(str(path), 'unchanged')
        with patch('ci_packages.sha256', side_effect=checksum):
            initial = input_key(entry, tracked, {'rust': '1.93'})
            hashes[str(Path('sources/pasta/src/lib.rs').resolve())] = 'changed'
            self.assertEqual(initial, input_key(entry, tracked, {'rust': '1.93'}))
            hashes[str(Path('sources/minato/src/lib.rs').resolve())] = 'changed'
            self.assertNotEqual(initial, input_key(entry, tracked, {'rust': '1.93'}))
            hashes.clear()
            self.assertNotEqual(initial, input_key(entry, tracked, {'rust': '1.94'}))
            changed = copy.deepcopy(entry)
            changed['revision'] += 1
            self.assertNotEqual(initial, input_key(changed, tracked, {'rust': '1.93'}))
            hashes[str(Path('scripts/ci_packages.py').resolve())] = 'changed'
            self.assertNotEqual(initial, input_key(entry, tracked, {'rust': '1.93'}))

    def test_vendor_package_tracks_its_swift_adapter(self):
        entry = next(entry for entry in modules() if entry['id'] == 'kawari')
        tracked = ['native/Sources/KawariCore/KawariSession.swift', 'native/Package.swift']
        with patch('ci_packages.sha256', return_value='before'):
            first = input_key(entry, tracked, {})
        with patch('ci_packages.sha256', side_effect=lambda p: 'after' if p.name == 'KawariSession.swift' else 'before'):
            self.assertNotEqual(first, input_key(entry, tracked, {}))

    def test_reuse_preserves_bytes_checks_catalog_and_rejects_corruption(self):
        entry = next(entry for entry in modules() if entry['id'] == 'minato')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder = root / 'cache' / entry['id']
            folder.mkdir(parents=True)
            archive = folder / package_name(entry)
            archive.write_bytes(b'original ZIP bytes')
            (folder / 'record.json').write_text(json.dumps({'key': 'key', 'sha256': sha256(archive)}))
            with patch('ci_packages.verify_package') as verify:
                self.assertFalse(reuse(entry, 'different-key', root / 'cache', root / 'dist'))
                verify.assert_not_called()
                self.assertTrue(reuse(entry, 'key', root / 'cache', root / 'dist'))
                verify.assert_called_once_with(archive, entry)
                self.assertEqual(archive.read_bytes(), (root / 'dist' / archive.name).read_bytes())
                archive.write_bytes(b'corrupt')
                with self.assertRaisesRegex(ValueError, 'Corrupt package cache'):
                    reuse(entry, 'key', root / 'cache', root / 'dist')
