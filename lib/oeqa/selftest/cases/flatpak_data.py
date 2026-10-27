#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# The flatpak data partition flatpak-cross-install lays out at parse time.
#
#   oe-selftest -r flatpak_data

import os

from oeqa.selftest.case import OESelftestTestCase
from oeqa.utils.commands import bitbake, get_bb_vars

IMAGE = 'flatpak-minimal-image'
CONFIG = ('INIT_MANAGER = "systemd"\n'
          'DISTRO_FEATURES:append = " polkit"\n'
          'FLATPAK_DEPLOY_MODE:pn-%s = "partition"\n' % IMAGE)
# The generic layout, on top of a base layout the test writes.
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
        """The partition is mounted by label, carries its directories and grows."""
        self.write_config(CONFIG)
        v = get_bb_vars(['FLATPAK_DATA_FSTAB', 'FLATPAK_DATA_LABEL', 'FLATPAK_DATA_MOUNT',
                         'FLATPAK_DATA_IMAGE', 'FLATPAK_DATA_WKS_PART', 'IMAGE_INSTALL'], IMAGE)
        self.assertEqual(v['FLATPAK_DATA_FSTAB'].split()[:3],
                         ['LABEL=%s' % v['FLATPAK_DATA_LABEL'], v['FLATPAK_DATA_MOUNT'], 'ext4'])
        self.assertIn('x-systemd.growfs', v['FLATPAK_DATA_FSTAB'])
        self.assertIn('vfpk-growpart', v['IMAGE_INSTALL'].split())
        self.assertIn('file=%s' % v['FLATPAK_DATA_IMAGE'], v['FLATPAK_DATA_WKS_PART'])
        self.assertIn('--label %s' % v['FLATPAK_DATA_LABEL'], v['FLATPAK_DATA_WKS_PART'])

    def test_partition_without_growing(self):
        """FLATPAK_DATA_GROW = "0" keeps the partition at its built size."""
        self.write_config(CONFIG + 'FLATPAK_DATA_GROW:pn-%s = "0"\n' % IMAGE)
        v = get_bb_vars(['FLATPAK_DATA_FSTAB', 'IMAGE_INSTALL'], IMAGE)
        self.assertNotIn('x-systemd.growfs', v['FLATPAK_DATA_FSTAB'])
        self.assertNotIn('vfpk-growpart', v['IMAGE_INSTALL'].split())

    def test_data_dirs_need_system_installation(self):
        self.parse_fails('FLATPAK_DATA_DIRS:pn-%s = "/home"\n' % IMAGE,
                         'FLATPAK_DATA_DIRS must include')

    def test_data_dirs_must_not_nest(self):
        self.parse_fails('FLATPAK_DATA_DIRS:pn-%s = "/var/lib/flatpak /var/lib/flatpak/x"\n' % IMAGE,
                         'must not nest')

    def test_data_dirs_need_distinct_names(self):
        self.parse_fails('FLATPAK_DATA_DIRS:pn-%s = "/var/lib/flatpak /opt/flatpak"\n' % IMAGE,
                         'would share')

    def test_wks_adds_partition_to_base_layout(self):
        """flatpak-data.wks.in is the base layout, expanded, with the data partition last."""
        base = os.path.join(self.builddir, 'flatpak-data-base.wks.in')
        with open(base, 'w') as f:
            f.write('part / --source rootfs --fstype=ext4 --label root-${MACHINE}\n'
                    'bootloader --ptable gpt\n')
        self.add_command_to_tearDown('rm -f %s' % base)
        self.write_config(CONFIG + WIC + BASE % (IMAGE, base))
        result = bitbake('-e %s' % IMAGE)
        template = result.output.split('\n_WKS_TEMPLATE="', 1)[1].split('\n"\n', 1)[0]
        parts = [l.strip(' \\') for l in template.split('\n') if l.startswith('part ')]
        v = get_bb_vars(['MACHINE', 'FLATPAK_DATA_LABEL'], IMAGE)
        self.assertEqual(len(parts), 2, msg=template)
        self.assertIn('--label root-%s' % v['MACHINE'], parts[0])
        self.assertIn('--label %s' % v['FLATPAK_DATA_LABEL'], parts[1])

    def test_wks_needs_base_layout(self):
        self.parse_fails(WIC, 'needs the machine\'s layout in FLATPAK_DATA_BASE_WKS')

    def test_wks_base_layout_must_exist(self):
        self.parse_fails(WIC + BASE % (IMAGE, 'missing.wks'), 'is not in WKS_SEARCH_PATH')
