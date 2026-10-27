#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# The SDK developers build apps against with flatpak-builder, and the
# developer repository it is published in.
#
#   oe-selftest -r flatpak_sdk

import base64
import configparser
import os
import shutil
import tempfile

from oeqa.selftest.case import OESelftestTestCase
from oeqa.utils.commands import bitbake, get_bb_var, get_bb_vars, runCmd


class FlatpakSdkTests(OESelftestTestCase):

    def sdk_repo(self):
        bitbake('flatpak-platform-sdk-image')
        v = get_bb_vars(['FLATPAK_DEPLOY_DIR', 'FLATPAK_DEPLOY_ARCH'], 'flatpak-platform-sdk-image')
        repo = os.path.join(v['FLATPAK_DEPLOY_DIR'], 'refs', v['FLATPAK_DEPLOY_ARCH'],
                            'flatpak-platform-sdk-image', 'repo')
        self.assertTrue(os.path.isfile(os.path.join(repo, 'config')), msg='no SDK repository at %s' % repo)
        bitbake('ostree-native -c addto_recipe_sysroot')
        return repo

    def ostree(self, repo, *args):
        return runCmd(['oe-run-native', 'ostree-native', 'ostree', '--repo=%s' % repo] + list(args)).output

    def gpg(self, home, *args):
        return runCmd(['oe-run-native', 'gnupg-native', 'gpg', '--homedir', home, '--batch'] + list(args)).output

    def fingerprints(self, home, secret=False):
        out = self.gpg(home, '--with-colons', '--list-secret-keys' if secret else '--list-keys')
        return [line.split(':')[9] for line in out.splitlines() if line.startswith('fpr:')]

    def test_sdk_has_flatpak_builder_tools(self):
        """The SDK names its runtime and carries what flatpak-builder runs."""
        repo = self.sdk_repo()
        refs = [r for r in self.ostree(repo, 'refs').split() if '.Sdk/' in r]
        self.assertEqual(len(refs), 1, msg='expected one SDK ref, found %s' % refs)
        metadata = self.ostree(repo, 'cat', refs[0], '/metadata')
        self.assertIn('runtime=%s/' % get_bb_var('FLATPAK_PLATFORM_ID', 'flatpak-platform-sdk-image'),
                      metadata, msg='the SDK does not name the Platform:\n%s' % metadata)
        for tool in ('gcc', 'cmake', 'meson', 'ninja', 'pkg-config', 'python3', 'eu-strip', 'debugedit'):
            self.ostree(repo, 'ls', refs[0], '/files/bin/%s' % tool)

    def test_publish_url_needs_signing_key(self):
        """A published remote file carries the signing key, so a URL without one is refused."""
        self.write_config('FLATPAK_PUBLISH_REMOTE_URL:pn-flatpak-repo-index-dev = "https://example.invalid/repo-dev"\n'
                          'FLATPAK_GPGID:pn-flatpak-repo-index-dev = ""\n')
        result = bitbake('-n flatpak-repo-index-dev', ignore_status=True)
        self.assertNotEqual(result.status, 0, msg='flatpak-repo-index-dev parsed without a signing key')
        self.assertIn('FLATPAK_GPGID is not', result.output)

    def test_flatpakrepo_carries_signing_key(self):
        """The remote file names the URL and carries the public key the repository is signed with."""
        self.sdk_repo()
        bitbake('gnupg-native -c addto_recipe_sysroot')
        # A throwaway key made for this test, in a home of its own; the layer
        # itself never makes one.
        home = tempfile.mkdtemp(prefix='vfpk-gpg-')
        imported = tempfile.mkdtemp(prefix='vfpk-gpg-')
        try:
            os.chmod(home, 0o700)
            os.chmod(imported, 0o700)
            self.gpg(home, '--pinentry-mode', 'loopback', '--passphrase', '',
                     '--quick-gen-key', 'flatpak-minimal selftest', 'default', 'default', 'never')
            fpr = self.fingerprints(home, secret=True)[0]
            url = 'https://example.invalid/repo-dev'
            self.write_config('FLATPAK_GPGID:pn-flatpak-repo-index-dev = "%s"\n'
                              'FLATPAK_GPGHOME:pn-flatpak-repo-index-dev = "%s"\n'
                              'FLATPAK_PUBLISH_REMOTE_URL:pn-flatpak-repo-index-dev = "%s"\n' % (fpr, home, url))
            bitbake('flatpak-repo-index-dev')

            v = get_bb_vars(['FLATPAK_PUBLISH_REPO', 'FLATPAK_PUBLISH_REMOTE_NAME'], 'flatpak-repo-index-dev')
            keyfile = configparser.ConfigParser(interpolation=None)
            keyfile.optionxform = str
            path = os.path.join(v['FLATPAK_PUBLISH_REPO'], v['FLATPAK_PUBLISH_REMOTE_NAME'] + '.flatpakrepo')
            self.assertEqual(keyfile.read(path), [path], msg='%s was not written' % path)
            repo = keyfile['Flatpak Repo']
            self.assertEqual(repo['Url'], url)
            key = os.path.join(imported, 'key.gpg')
            with open(key, 'wb') as f:
                f.write(base64.b64decode(repo['GPGKey']))
            self.gpg(imported, '--import', key)
            self.assertEqual(self.fingerprints(imported), [fpr], msg='GPGKey is not the signing key')
        finally:
            for h in (home, imported):
                runCmd(['oe-run-native', 'gnupg-native', 'gpgconf', '--homedir', h, '--kill', 'all'],
                       ignore_status=True)
                shutil.rmtree(h, ignore_errors=True)
            # Back to the unpublished repository, without the test's remote file.
            self.write_config('')
            bitbake('flatpak-repo-index-dev', ignore_status=True)
