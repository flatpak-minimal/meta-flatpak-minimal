#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Parse-time checks of the flatpak data partition: oe-selftest -r flatpak_data

import os

from oeqa.selftest.case import OESelftestTestCase
from oeqa.utils.commands import bitbake, get_bb_vars

IMAGE = 'flatpak-minimal-image'
PARTITION = ('INIT_MANAGER = "systemd"\n'
             'DISTRO_FEATURES:append = " polkit"\n'
             'FLATPAK_DEPLOY_MODE:pn-%s = "partition"\n' % IMAGE)
CONFIG = PARTITION + 'FLATPAK_DATA_GROW:pn-%s = "1"\n' % IMAGE
DIRS = 'FLATPAK_DATA_DIRS:pn-%s = "/var/lib/flatpak /home"\n' % IMAGE
USER = ('FLATPAK_INSTALL_SCOPE:pn-%s = "user"\n'
        'FLATPAK_INSTALL_USER:pn-%s = "vfpktest"\n' % (IMAGE, IMAGE))
WIC = ('IMAGE_FSTYPES:append:pn-%s = " wic"\n'
       'WKS_FILE:pn-%s = "flatpak-data.wks.in"\n' % (IMAGE, IMAGE))
BASE = 'FLATPAK_DATA_BASE_WKS:pn-%s = "%s"\n'


class FlatpakDataPartitionTests(OESelftestTestCase):

    def parse_fails(self, config, message):
        self.write_config(CONFIG + config)
        result = bitbake('-e %s' % IMAGE, ignore_status=True)
        self.assertNotEqual(result.status, 0, msg='%s parsed with:\n%s' % (IMAGE, config))
        self.assertIn(message, result.output)

    def test_partition_layout(self):
        """The fstab entry and wic line of a grown partition."""
        self.write_config(CONFIG)
        v = get_bb_vars(['FLATPAK_DATA_FSTAB', 'FLATPAK_DATA_LABEL', 'localstatedir',
                         'FLATPAK_DATA_IMAGE_LINK', 'FLATPAK_DATA_WKS_PART', 'FLATPAK_DATA_PART_TYPE',
                         'IMGDEPLOYDIR', 'IMAGE_LINK_NAME'], IMAGE)
        self.assertEqual(v['FLATPAK_DATA_FSTAB'].split()[:3],
                         ['LABEL=%s' % v['FLATPAK_DATA_LABEL'], v['localstatedir'] + '/lib/flatpak', 'ext4'])
        self.assertIn('x-systemd.growfs', v['FLATPAK_DATA_FSTAB'])
        self.assertIn('--part-type %s' % v['FLATPAK_DATA_PART_TYPE'], v['FLATPAK_DATA_WKS_PART'])
        # The link, not IMAGE_NAME: that carries the run's DATETIME.
        self.assertEqual(v['FLATPAK_DATA_IMAGE_LINK'],
                         os.path.join(v['IMGDEPLOYDIR'], v['IMAGE_LINK_NAME'] + '.vfpk-data.ext4'))
        self.assertIn('file=%s"' % v['FLATPAK_DATA_IMAGE_LINK'], v['FLATPAK_DATA_WKS_PART'])
        self.assertIn('--label %s' % v['FLATPAK_DATA_LABEL'], v['FLATPAK_DATA_WKS_PART'])

    def test_partition_without_growing(self):
        """Growing is off by default."""
        self.write_config(PARTITION)
        v = get_bb_vars(['FLATPAK_DATA_FSTAB', 'FLATPAK_DATA_WKS_PART'], IMAGE)
        self.assertNotIn('x-systemd.growfs', v['FLATPAK_DATA_FSTAB'])
        self.assertNotIn('--part-type', v['FLATPAK_DATA_WKS_PART'])

    def write_base(self, text):
        base = os.path.join(self.builddir, 'flatpak-data-base.wks.in')
        with open(base, 'w') as f:
            f.write(text)
        self.add_command_to_tearDown('rm -f %s' % base)
        return base

    def test_partition_default_mount(self):
        """Without FLATPAK_DATA_DIRS the partition is mounted at /var/lib/flatpak."""
        self.write_config(PARTITION)
        v = get_bb_vars(['FLATPAK_DATA_FSTAB', 'localstatedir'], IMAGE)
        self.assertEqual(v['FLATPAK_DATA_FSTAB'].split()[1], v['localstatedir'] + '/lib/flatpak')

    def test_partition_data_dirs_mount(self):
        """With FLATPAK_DATA_DIRS the partition is mounted at FLATPAK_DATA_MOUNT."""
        self.write_config(PARTITION + DIRS)
        v = get_bb_vars(['FLATPAK_DATA_FSTAB', 'FLATPAK_DATA_MOUNT'], IMAGE)
        self.assertEqual(v['FLATPAK_DATA_FSTAB'].split()[1], v['FLATPAK_DATA_MOUNT'])

    def test_user_scope_needs_data_dirs(self):
        self.parse_fails(USER, 'needs FLATPAK_DATA_DIRS')

    def test_data_dirs_need_system_installation(self):
        self.parse_fails('FLATPAK_DATA_DIRS:pn-%s = "/home"\n' % IMAGE,
                         'FLATPAK_DATA_DIRS must include')

    def test_data_dirs_must_not_nest(self):
        self.parse_fails('FLATPAK_DATA_DIRS:pn-%s = "/var/lib/flatpak /var/lib/flatpak/x"\n' % IMAGE,
                         'must not nest')

    def test_data_dirs_need_distinct_names(self):
        self.parse_fails('FLATPAK_DATA_DIRS:pn-%s = "/var/lib/flatpak /opt/flatpak"\n' % IMAGE,
                         'would share')

    def wks_template(self, config):
        self.write_config(CONFIG + WIC + config)
        result = bitbake('-e %s' % IMAGE)
        return result.output.split('\n_WKS_TEMPLATE="', 1)[1].split('\n"\n', 1)[0]

    def test_wks_adds_partition_to_base_layout(self):
        """The base layout, expanded, then the data partition."""
        base = self.write_base('part / --source rootfs --fstype=ext4 --label root-${MACHINE}\n'
                               'bootloader --ptable gpt\n')
        template = self.wks_template(BASE % (IMAGE, base))
        parts = [l.strip(' \\') for l in template.split('\n') if l.startswith('part ')]
        v = get_bb_vars(['MACHINE', 'FLATPAK_DATA_LABEL'], IMAGE)
        self.assertEqual(len(parts), 2, msg=template)
        self.assertIn('--label root-%s' % v['MACHINE'], parts[0])
        self.assertIn('--label %s' % v['FLATPAK_DATA_LABEL'], parts[1])
        self.assertEqual(template.count('bootloader'), 1, msg=template)

    def test_wks_base_without_bootloader_gets_gpt(self):
        """A base with no bootloader line gets a GPT one."""
        base = self.write_base('part / --source rootfs --fstype=ext4 --label root\n')
        template = self.wks_template(BASE % (IMAGE, base))
        self.assertIn('bootloader --ptable gpt', [l.strip(' \\') for l in template.split('\n')], msg=template)

    def test_wks_base_without_bootloader_kept_without_growing(self):
        base = self.write_base('part / --source rootfs --fstype=ext4 --label root\n')
        self.write_config(PARTITION + WIC + BASE % (IMAGE, base))
        result = bitbake('-e %s' % IMAGE)
        template = result.output.split('\n_WKS_TEMPLATE="', 1)[1].split('\n"\n', 1)[0]
        self.assertNotIn('bootloader', template, msg=template)

    def test_wks_msdos_base_without_growing(self):
        """An msdos base is fine when the partition does not grow."""
        base = self.write_base('part / --source rootfs --fstype=ext4 --label root\n'
                               'bootloader --ptable msdos\n')
        self.write_config(PARTITION + WIC + BASE % (IMAGE, base))
        self.assertEqual(bitbake('-e %s' % IMAGE, ignore_status=True).status, 0)

    def test_wks_msdos_base_fails_growing(self):
        base = self.write_base('part / --source rootfs --fstype=ext4 --label root\n'
                               'bootloader --ptable msdos\n')
        self.parse_fails(WIC + BASE % (IMAGE, base), 'needs a GPT disk')

    def test_wks_own_msdos_layout_fails_growing(self):
        """An image's own layout without a bootloader line is msdos."""
        layout = self.write_base('part / --source rootfs --fstype=ext4 --label root\n'
                                 '${FLATPAK_DATA_WKS_PART}\n')
        self.parse_fails('IMAGE_FSTYPES:append:pn-%s = " wic"\nWKS_FILE:pn-%s = "%s"\n'
                         % (IMAGE, IMAGE, layout), 'needs a GPT disk')

    def test_wks_needs_base_layout(self):
        self.parse_fails(WIC, 'needs the machine\'s layout in FLATPAK_DATA_BASE_WKS')

    def test_wks_base_layout_must_exist(self):
        self.parse_fails(WIC + BASE % (IMAGE, 'missing.wks'), 'is not in WKS_SEARCH_PATH')
