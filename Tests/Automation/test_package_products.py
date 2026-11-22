import json
from pathlib import Path
import subprocess
import unittest
import unicodedata


class PackageProductsTests(unittest.TestCase):
    def test_executable_products_have_distinct_case_insensitive_paths(self):
        root = Path(__file__).resolve().parents[2]
        result = subprocess.run(
            ['swift', 'package', 'dump-package'],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        package = json.loads(result.stdout)
        names = [
            product['name']
            for product in package['products']
            if 'executable' in product['type']
        ]
        self.assertGreaterEqual(len(names), 2)
        normalized = [unicodedata.normalize('NFD', name).casefold() for name in names]
        self.assertEqual(
            len(normalized),
            len(set(normalized)),
            f'Executable products collide on a case insensitive filesystem: {names}',
        )


if __name__ == '__main__':
    unittest.main()
