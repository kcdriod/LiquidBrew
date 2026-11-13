from pathlib import Path
import os
import subprocess
import textwrap
import unittest


class BranchPolicyTests(unittest.TestCase):
    def test_actual_workflow_route_check(self):
        workflow = Path(__file__).resolve().parents[2] / '.github/workflows/pr-policy.yml'
        shell = textwrap.dedent(workflow.read_text().split('        run: |\n', 1)[1])
        cases = [
            ('develop', 'feature/change', 'contributor/fork', True),
            ('develop', 'master', 'kcdriod/LiquidBrew', True),
            ('master', 'develop', 'kcdriod/LiquidBrew', True),
            ('master', 'develop', 'contributor/fork', False),
            ('master', 'feature/change', 'kcdriod/LiquidBrew', False),
            ('master', 'main', 'kcdriod/LiquidBrew', False),
        ]
        for base, head, repo, allowed in cases:
            with self.subTest(base=base, head=head, repo=repo):
                env = dict(os.environ, BASE_BRANCH=base, HEAD_BRANCH=head,
                           HEAD_REPOSITORY=repo, TARGET_REPOSITORY='kcdriod/LiquidBrew')
                result = subprocess.run(['bash', '-eu', '-c', shell], env=env, capture_output=True)
                self.assertEqual(result.returncode == 0, allowed)
