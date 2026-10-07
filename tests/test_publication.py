import argparse
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / 'scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


publish = load('publish')
check_plan = load('check_plan')
check_backend = load('check_backend')
check_dns = load('check_dns')
SHA = 'a' * 40


class FakeAWS:
    def __init__(self):
        self.objects = {}
        self.calls = []
        self.fail_live_html = False

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ('cloudfront', 'create-invalidation'):
            return json.dumps({'Invalidation': {'Id': 'I123'}})
        if args[:2] == ('cloudfront', 'wait'):
            return ''
        _, command, source, target, *options = args
        assert command == 'cp'
        if source.startswith('s3://'):
            if source not in self.objects:
                raise subprocess.CalledProcessError(1, args, stderr='NoSuchKey')
            data = self.objects[source]
            if target == '-':
                return data.decode()
            Path(target).write_bytes(data)
        else:
            if self.fail_live_html and target == 's3://live/index.html':
                raise subprocess.CalledProcessError(1, args, stderr='Upload failed')
            self.objects[target] = Path(source).read_bytes()
        return ''


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        (self.directory / 'index.html').write_text('<html>first</html>')
        (self.directory / 'app.abcdef123.js').write_text('first')
        (self.directory / 'robots.txt').write_text('User-agent: *')
        self.fake = FakeAWS()
        self.patch = patch.object(publish, 'aws', self.fake)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def args(self, command='publish', sha=SHA):
        return argparse.Namespace(command=command, directory=str(self.directory),
                                  bucket='live', release_bucket='archive', distribution_id='D123', release_id=sha)

    def test_publish_archives_then_assets_then_html_and_waits(self):
        publish.run(self.args())
        live = [call for call in self.fake.calls if len(call) > 3 and call[3].startswith('s3://live/')]
        self.assertTrue(live[-1][3].endswith('/index.html'))
        asset = next(call for call in live if call[3].endswith('.js'))
        self.assertIn(publish.ASSET_CACHE, asset)
        self.assertIn(publish.HTML_CACHE, live[-1])
        self.assertIn(('cloudfront', 'wait', 'invalidation-completed', '--distribution-id', 'D123', '--id', 'I123'), self.fake.calls)
        self.assertEqual(json.loads(self.fake.objects['s3://archive/current.json'])['release_id'], SHA)

    def test_interrupted_publication_has_archive_but_no_completion_marker(self):
        self.fake.fail_live_html = True
        with self.assertRaises(subprocess.CalledProcessError):
            publish.run(self.args())
        self.assertIn(f's3://archive/releases/{SHA}/manifest.json', self.fake.objects)
        self.assertNotIn('s3://archive/current.json', self.fake.objects)
        self.assertFalse(any(call[0] == 'cloudfront' for call in self.fake.calls))

    def test_rollback_restores_verified_content_and_keeps_previous_assets(self):
        publish.run(self.args())
        self.fake.objects['s3://live/index.html'] = b'newer'
        self.fake.objects['s3://live/old-hash.js'] = b'cached reference'
        publish.run(self.args('rollback'))
        self.assertEqual(self.fake.objects['s3://live/index.html'], b'<html>first</html>')
        self.assertIn('s3://live/old-hash.js', self.fake.objects)

    def test_bad_archive_checksum_fails_before_live_writes(self):
        publish.run(self.args())
        self.fake.objects[f's3://archive/releases/{SHA}/objects/index.html'] = b'corrupt'
        self.fake.calls.clear()
        with self.assertRaisesRegex(ValueError, 'checksum'):
            publish.run(self.args('rollback'))
        self.assertFalse(any(len(call) > 3 and call[3].startswith('s3://live/') for call in self.fake.calls))

    def test_same_sha_different_build_cannot_overwrite_release(self):
        publish.run(self.args())
        (self.directory / 'index.html').write_text('different')
        self.fake.calls.clear()
        with self.assertRaisesRegex(ValueError, 'different content'):
            publish.run(self.args())
        self.assertFalse(any(call[0] == 'cloudfront' for call in self.fake.calls))

    def test_missing_release_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'manifest'):
            publish.run(self.args('rollback'))

    def test_invalid_artifacts_and_paths(self):
        for key in ['../secret', '/index.html', 'foo/../bar', 'a\\b', 'a\nkey']:
            with self.assertRaises(ValueError):
                publish.safe_path(key)
        (self.directory / '.env').write_text('secret')
        with self.assertRaisesRegex(ValueError, 'Hidden'):
            publish.inventory(self.directory)
        (self.directory / '.env').unlink()
        (self.directory / 'link').symlink_to(self.directory / 'index.html')
        with self.assertRaisesRegex(ValueError, 'Symlinks'):
            publish.inventory(self.directory)


class InfrastructureGuardTests(unittest.TestCase):
    def test_migration_rejects_replacement_but_accepts_update_and_forget(self):
        def change(actions):
            return {'address': 'module.site.aws_s3_bucket.s3_bucket[0]', 'type': 'aws_s3_bucket', 'change': {'actions': actions}}
        self.assertEqual(check_plan.destructive_changes({'resource_changes': [change(['update']), change(['forget'])]}), [])
        self.assertEqual(len(check_plan.destructive_changes({'resource_changes': [change(['delete', 'create'])]})), 1)

    def test_ci_requires_remote_encrypted_locked_backend(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'main.tf').write_text('# comment\nterraform { backend "s3" {} }')
            config = root / 'backend.hcl'
            settings = 'bucket="state"\nkey="sites/test.tfstate"\nregion="us-east-1"\nencrypt=true\nuse_lockfile=true\n'
            config.write_text(settings)
            check_backend.check(root, 'backend.hcl')
            config.write_text(settings.replace('use_lockfile=true', 'use_lockfile=false'))
            with self.assertRaises(ValueError):
                check_backend.check(root, 'backend.hcl')
            config.write_text(settings)
            (root / 'main.tf').write_text('terraform { backend "local" {} }')
            with self.assertRaises(ValueError):
                check_backend.check(root, 'backend.hcl')

    def test_dns_rejects_wrong_delegation_even_when_ns_exist(self):
        expected = {'ns-1.awsdns.com', 'ns-2.awsdns.net'}
        def records(name, kind, server=None):
            if name == 'com':
                return {'a.gtld-servers.net'}
            if server == 'a.gtld-servers.net':
                return {'ns.old-provider.com'}
            return expected
        with patch.object(check_dns, 'records', records):
            self.assertFalse(check_dns.delegated('example.com', expected))

    def test_dns_parses_parent_authority_and_rejects_unrelated_records(self):
        response = 'example.com. 172800 IN NS ns-1.awsdns.com.\nexample.com. 172800 IN NS ns-2.awsdns.net.\ncom. 300 IN NS a.gtld-servers.net.\n'
        with patch.object(check_dns.subprocess, 'check_output', return_value=response):
            self.assertEqual(check_dns.records('example.com', 'NS', 'a.gtld-servers.net'),
                             {'ns-1.awsdns.com', 'ns-2.awsdns.net'})

    def test_dns_accepts_matching_parent_and_zone_authorities(self):
        expected = {'ns-1.awsdns.com', 'ns-2.awsdns.net'}
        with patch.object(check_dns, 'records', side_effect=lambda name, kind, server=None:
                          {'a.gtld-servers.net'} if name == 'com' else expected):
            self.assertTrue(check_dns.delegated('example.com', expected))


if __name__ == '__main__':
    unittest.main()
