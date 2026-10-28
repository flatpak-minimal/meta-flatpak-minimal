#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Runtime checks for flatpak content installed at build time by
# flatpak-cross-install. Add "flatpak" to TEST_SUITES.

from oeqa.runtime.case import OERuntimeTestCase
from oeqa.core.decorator.depends import OETestDepends
from oeqa.runtime.decorator.package import OEHasPackage
from shlex import quote

INSTALLED_REFS = '/usr/share/vfpk/installed.refs'
TEST_APP = 'org.flatpak_minimal.Test.Hello'

# flatpak run needs a runtime directory, which a non-login ssh command does
# not get.
RUN_ENV = 'mkdir -p -m 0700 /run/vfpk-test && XDG_RUNTIME_DIR=/run/vfpk-test'


class FlatpakTest(OERuntimeTestCase):

    def flatpak(self, command, timeout=300, runtime=False):
        status, output = self.target.run('cat /usr/share/vfpk/installed.scope')
        scope = output.split() if status == 0 else ['system']
        self.assertIn(scope[0], ('system', 'user'))
        cmd = 'flatpak --%s %s' % (scope[0], command)
        if scope[0] == 'user':
            self.assertEqual(len(scope), 2, msg='user installation has no account')
            if runtime:
                # Keep the test's runtime separate from the live GUI session.
                cmd = 'XDG_RUNTIME_DIR="$HOME/.cache/vfpk-test-runtime"; export XDG_RUNTIME_DIR; mkdir -p -m 0700 "$XDG_RUNTIME_DIR"; ' + cmd
            cmd = 'su - %s -c %s' % (quote(scope[1]), quote(cmd))
        elif runtime:
            cmd = RUN_ENV + ' ' + cmd
        return self.target.run(cmd, timeout=timeout)

    def installed_refs(self):
        status, output = self.target.run('cat %s' % INSTALLED_REFS)
        if status != 0:
            self.skipTest('%s not found: the image has no build-time flatpak content' % INSTALLED_REFS)
        refs = [line.split() for line in output.splitlines() if line.strip()]
        self.assertTrue(refs, msg='%s is empty' % INSTALLED_REFS)
        return refs

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    @OEHasPackage(['flatpak'])
    def test_flatpak_installed_refs(self):
        """Every ref the build installed is deployed at its commit, under its origin."""
        for ref, origin, commit in self.installed_refs():
            status, output = self.flatpak('info --show-origin --show-commit %s' % ref)
            self.assertEqual(status, 0, msg='flatpak info %s failed: %s' % (ref, output))
            self.assertEqual(output.split(), [origin, commit],
                             msg='%s: expected origin %s at %s, got: %s' % (ref, origin, commit, output))

    @OETestDepends(['flatpak.FlatpakTest.test_flatpak_installed_refs'])
    def test_flatpak_remotes(self):
        """Each origin is a configured remote with a URL."""
        status, output = self.flatpak('remotes --show-disabled --columns=name,url')
        self.assertEqual(status, 0, msg='flatpak remotes failed: %s' % output)
        remotes = dict((line.split() + [''])[:2] for line in output.splitlines() if line.strip())
        for ref, origin, commit in self.installed_refs():
            self.assertIn(origin, remotes, msg='%s: origin %s is not a remote' % (ref, origin))

    @OETestDepends(['flatpak.FlatpakTest.test_flatpak_installed_refs'])
    def test_flatpak_list_installations(self):
        """With a user installation, the account can list every installation."""
        status, output = self.target.run('cat /usr/share/vfpk/installed.scope')
        scope = output.split() if status == 0 else ['system']
        if scope[0] != 'user':
            self.skipTest('the image has a system installation')
        # Without the system installation, flatpak list with no scope fails.
        status, output = self.target.run('su - %s -c %s' % (quote(scope[1]), quote('flatpak list')))
        self.assertEqual(status, 0, msg='flatpak list as %s failed: %s' % (scope[1], output))

    @OETestDepends(['flatpak.FlatpakTest.test_flatpak_installed_refs'])
    def test_flatpak_repair(self):
        """The installation is consistent."""
        status, output = self.flatpak('repair --dry-run', timeout=600)
        self.assertEqual(status, 0, msg='flatpak repair failed: %s' % output)

    def mountinfo(self, path):
        """MAJOR:MINOR and root within the filesystem of the mount at PATH."""
        status, output = self.target.run("awk '$5 == \"%s\" {print $3, $4}' /proc/self/mountinfo" % path)
        lines = output.splitlines() if status == 0 else []
        return lines[-1].split() if lines else None

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    def test_flatpak_data_partition(self):
        """The data partition carries the installations and, grown, reaches the end of its disk."""
        if self.td.get('FLATPAK_DEPLOY_MODE') != 'partition':
            self.skipTest('the image has no flatpak data partition')
        mount = self.td.get('FLATPAK_DATA_MOUNT')
        data = self.mountinfo(mount)
        self.assertTrue(data, msg='the data partition is not mounted at %s' % mount)
        for path in self.td.get('FLATPAK_DATA_DIRS', '').split():
            self.assertEqual(self.mountinfo(path), [data[0], '/' + path.rstrip('/').rsplit('/', 1)[1]],
                             msg='%s is not bind-mounted from %s' % (path, mount))

        if self.td.get('FLATPAK_INSTALL_SCOPE') == 'user':
            user = self.td.get('FLATPAK_INSTALL_USER')
            status, output = self.target.run(
                'stat -c %%U "$(getent passwd %s | cut -d: -f6)/.local/share/flatpak/repo"' % quote(user))
            self.assertEqual((status, output.strip()), (0, user),
                             msg='the user installation does not belong to %s: %s' % (user, output))

        if self.td.get('FLATPAK_DATA_GROW') != '1':
            return
        # In 512-byte sectors; past the partition, only the backup GPT and
        # alignment remain once it has grown. Under runqemu the disk is the
        # image's size, so this only shows growth on a larger disk.
        status, output = self.target.run(
            'p=$(readlink -f /sys/dev/block/%s); echo $(cat $p/start) $(cat $p/size) $(cat $p/../size)' % data[0])
        self.assertEqual(status, 0, msg='cannot read the partition geometry: %s' % output)
        start, size, total = (int(n) for n in output.split())
        self.assertLess(total - start - size, 4096,
                        msg='the data partition leaves %d MiB unused at the end of its disk'
                            % ((total - start - size) // 2048))

    @OETestDepends(['flatpak.FlatpakTest.test_flatpak_installed_refs'])
    def test_flatpak_run(self):
        """The test app runs in its sandbox."""
        if not any(ref.startswith('app/%s/' % TEST_APP) for ref, _, _ in self.installed_refs()):
            self.skipTest('%s is not installed' % TEST_APP)
        status, output = self.flatpak('run %s' % TEST_APP, runtime=True)
        self.assertEqual(status, 0, msg='flatpak run %s failed: %s' % (TEST_APP, output))
        self.assertIn('vfpk-test-hello: id=%s' % TEST_APP, output,
                      msg='%s did not run under flatpak: %s' % (TEST_APP, output))
