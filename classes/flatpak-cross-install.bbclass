#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Install flatpak content into an image's system installation
# (/var/lib/flatpak) at build time.
#
# The content comes from flatpak-bundle packages: everything they install
# under ${FLATPAK_BUNDLES_DIR} is collected after the rootfs is assembled,
# installed by the target's own flatpak in a vfpk QEMU guest, and removed from
# the rootfs again. Put bundle packages in the image with IMAGE_INSTALL, or
# list them in BUNDLED_FLATPAKS to add them and set options:
#
#   BUNDLED_FLATPAKS = "flathub-freedesktop-platform flutter-remote-manager:autostart"
#
# Each entry is PN[:option...]:
#   autostart  generate and enable flatpak-app-<ID>.service for every app in
#              the package. The unit runs 'flatpak run --system <ID>' as
#              FLATPAK_APP_USER (varflag [PN] overrides it per package), with
#              the KEY=VALUE pairs of FLATPAK_APP_ENV as its environment, or
#              FLATPAK_SERVICE_FILE[PN] (an absolute path) replaces the unit.
#   external   do not add PN to IMAGE_INSTALL; the package reaches the image
#              some other way, for example through a packagegroup.
#
# Refs mirrored from a remote are installed from a local copy under the
# remote's real name, so each records that remote as its origin, and the
# remote is then pointed back at its real URL. Remotes come from the image's
# own /etc/flatpak/remotes.d, applied by flatpak in the guest as it would on
# the device, so every remote the content uses must be in flatpak-remotes
# (FLATPAK_REMOTES), and the device has nothing left to apply. A bundle
# installs under the origin remote it carries.
#
# An installation already in the rootfs is kept: the guest starts from it and
# adds to it. The resulting refs are listed, one "REF ORIGIN COMMIT" per
# line, in ${FLATPAK_INSTALLED_REFS} for launchers.
#
# Needs the vfpk-<arch> multiconfig for the image's architecture in
# BBMULTICONFIG (see conf/multiconfig). An image without flatpak content
# builds without it.

inherit flatpak-common

BUNDLED_FLATPAKS ??= ""

FLATPAK_APP_USER ??= ""
FLATPAK_APP_ENV ??= ""

FLATPAK_INSTALLED_REFS = "${datadir}/vfpk/installed.refs"

# Guest timeout in seconds; empty derives it from the size of the content.
FLATPAK_INSTALL_TIMEOUT ??= ""
FLATPAK_INSTALL_MEMORY ??= "2048"
# Guest CPUs. nproc inside a task follows OMP_NUM_THREADS, so ask for them.
FLATPAK_INSTALL_SMP ??= "${@min(4, len(os.sched_getaffinity(0)))}"

DEPENDS += "vfpk-native ostree-native"

python () {
    import re

    mc = d.getVar('VFPK_MULTICONFIG')
    if not mc:
        raise bb.parse.SkipRecipe("vfpk has no guest for TARGET_ARCH %s" % d.getVar('TARGET_ARCH'))
    have_mc = mc in (d.getVar('BBMULTICONFIG') or '').split()

    entries = (d.getVar('BUNDLED_FLATPAKS') or '').split()
    if entries and not have_mc:
        raise bb.parse.SkipRecipe("BUNDLED_FLATPAKS needs the vfpk guest: add %s to BBMULTICONFIG" % mc)
    if have_mc:
        d.appendVarFlag('do_rootfs', 'mcdepends',
                        ' mc:%s:%s:vfpk-initramfs-create:do_deploy' % (d.getVar('BB_CURRENT_MC'), mc))

    for entry in entries:
        fields = entry.split(':')
        pn, options = fields[0], fields[1:]
        if not re.fullmatch(r'[a-z0-9][a-z0-9.+-]*', pn):
            bb.fatal("BUNDLED_FLATPAKS: '%s' is not a package name" % pn)
        for option in options:
            if option not in ('autostart', 'external'):
                bb.fatal("BUNDLED_FLATPAKS: unknown option '%s' in '%s'" % (option, entry))
        if 'external' not in options:
            d.appendVar('IMAGE_INSTALL', ' ' + pn)
        if 'autostart' in options:
            if not bb.utils.contains('DISTRO_FEATURES', 'systemd', True, False, d):
                bb.fatal("BUNDLED_FLATPAKS: autostart for %s needs systemd in DISTRO_FEATURES" % pn)
            unit = d.getVarFlag('FLATPAK_SERVICE_FILE', pn)
            if unit:
                if not os.path.isabs(unit):
                    bb.fatal("FLATPAK_SERVICE_FILE[%s] must be an absolute path" % pn)
                d.appendVarFlag('do_rootfs', 'file-checksums', ' %s:%s' % (unit, os.path.exists(unit)))
}

ROOTFS_POSTPROCESS_COMMAND += "flatpak_cross_install"
ROOTFS_POSTPROCESS_COMMAND:append = " flatpak_autostart_units"

do_rootfs[vardeps] += "BUNDLED_FLATPAKS FLATPAK_DEPLOY_MODE FLATPAK_APP_USER FLATPAK_APP_ENV \
    FLATPAK_SERVICE_FILE FLATPAK_INSTALL_TIMEOUT FLATPAK_INSTALL_MEMORY"
# Tuning only; the result does not depend on it.
flatpak_cross_install[vardepsexclude] += "FLATPAK_INSTALL_SMP"

FLATPAK_NAME_RE = "[A-Za-z0-9][A-Za-z0-9._-]*"
FLATPAK_REF_RE = "(app|runtime)/[A-Za-z0-9._-]+/[A-Za-z0-9_]+/[A-Za-z0-9._-]+"

def flatpak_read_bundles(d, bundles_dir):
    """Parse and check the .meta and .refs files flatpak-bundle installs."""
    import re

    name_re = d.getVar('FLATPAK_NAME_RE')
    ref_re = d.getVar('FLATPAK_REF_RE')
    bundles = []
    if not os.path.isdir(bundles_dir):
        return bundles
    for meta in sorted(f for f in os.listdir(bundles_dir) if f.endswith('.meta')):
        pn = meta[:-len('.meta')]
        props = {}
        with open(os.path.join(bundles_dir, meta)) as f:
            for line in f:
                key, sep, value = line.rstrip('\n').partition('=')
                if sep:
                    props[key] = value
        kind = props.get('kind')
        path = props.get('path', '')
        remote = props.get('remote', '')
        if kind not in ('repo', 'bundle'):
            bb.fatal("%s: unknown kind '%s'" % (meta, kind))
        # The path stays inside the bundles directory.
        if not re.fullmatch(r'(repos|bundles)/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?', path) or '..' in path:
            bb.fatal("%s: bad path '%s'" % (meta, path))
        if kind == 'repo' and not re.fullmatch(name_re, remote):
            bb.fatal("%s: bad remote '%s'" % (meta, remote))

        refs = []
        with open(os.path.join(bundles_dir, pn + '.refs')) as f:
            for line in f:
                fields = line.split()
                if not fields:
                    continue
                if len(fields) != 2 or not re.fullmatch(ref_re, fields[0]) or \
                   not re.fullmatch(r'[0-9a-f]{64}|-', fields[1]):
                    bb.fatal("%s.refs: bad line '%s'" % (pn, line.strip()))
                if fields[0].split('/')[2] != d.getVar('FLATPAK_ARCH'):
                    bb.fatal("%s: %s is not for flatpak arch %s" % (pn, fields[0], d.getVar('FLATPAK_ARCH')))
                refs.append((fields[0], fields[1]))
        if not refs:
            bb.fatal("%s.refs lists no refs" % pn)
        if kind == 'bundle' and len(refs) != 1:
            bb.fatal("%s.refs: a bundle holds exactly one ref" % pn)

        bundles.append({'pn': pn, 'kind': kind, 'path': path, 'remote': remote, 'refs': refs,
                        'allow_no_origin': props.get('allow_no_origin') == '1'})
    return bundles

def flatpak_run(d, args, unload_pseudo=True):
    """Run a host tool from the native sysroot; fail the build with its output."""
    import subprocess
    env = dict(os.environ)
    env['PATH'] = '%s:%s:%s' % (d.getVar('STAGING_BINDIR_NATIVE'), d.getVar('STAGING_SBINDIR_NATIVE'),
                                env.get('PATH', ''))
    env['TMPDIR'] = d.getVar('FLATPAK_TMP')
    # Files outside the rootfs, and QEMU, have no business under pseudo.
    if unload_pseudo:
        env['PSEUDO_UNLOAD'] = '1'
    proc = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if proc.returncode != 0:
        bb.fatal("%s failed with exit status %d:\n%s" % (args[0], proc.returncode, proc.stdout))
    return proc.stdout

def flatpak_guest_script(d, remotes, bundles):
    """The shell script the guest runs; every value is quoted."""
    from shlex import quote

    lines = [
        'set -eu',
        'repo=/var/lib/flatpak/repo',
        'in=$VFPK_INPUT',
        'flatpak_install() { flatpak install --system -y --noninteractive "$@"; }',
        'remote_config() { ostree --repo="$repo" config "$1" "remote \\"$2\\".$3" ${4:+"$4"}; }',
        # Filters are referenced by absolute path from the .flatpakrepo files.
        'if [ -d "$in/filters" ]; then mkdir -p /etc/flatpak/filters && cp "$in"/filters/* /etc/flatpak/filters/; fi',
        # The image's remotes.d, applied by flatpak itself the first time it
        # opens the installation, as on the device: each file becomes a
        # remote unless one of that name exists, and is recorded as applied.
        # One left unapplied would make the first unprivileged flatpak
        # command on the device need root to apply it.
        'if [ -d "$in/remotes.d" ]; then mkdir -p /etc/flatpak/remotes.d && cp "$in"/remotes.d/* /etc/flatpak/remotes.d/; fi',
        'flatpak remotes --system --show-disabled --columns=name > /tmp/remotes',
    ]

    for i, remote in enumerate(remotes):
        r = quote(remote)
        lines += [
            'echo "vfpk: remote %s"' % r,
            'grep -qx %s /tmp/remotes || { echo "vfpk: the installation has no remote %s"; exit 1; }' % (r, r),
            'url_%d=$(remote_config get %s url)' % (i, r),
            # A packaged repository's summary is regenerated, so unsigned;
            # commit signatures are still verified.
            'if gvs=$(remote_config get %s gpg-verify-summary 2>/dev/null); then gvs_%d=$gvs; else gvs_%d=; fi'
                % (r, i, i),
            'flatpak remote-modify --system --url="file://$in/repos/"%s %s' % (r, r),
            'remote_config set %s gpg-verify-summary false' % r,
        ]

    # Runtimes first, from every remote, so apps find theirs installed.
    for kind in ('runtime', 'app'):
        for remote, refs in remotes.items():
            selected = sorted(ref for ref in refs if ref.startswith(kind + '/'))
            if selected:
                lines.append('flatpak_install --or-update %s %s' % (quote(remote), ' '.join(quote(r) for r in selected)))

    for i, remote in enumerate(remotes):
        r = quote(remote)
        lines += [
            'flatpak remote-modify --system --url="$url_%d" %s' % (i, r),
            'if [ -n "$gvs_%d" ]; then remote_config set %s gpg-verify-summary "$gvs_%d"; '
            'else remote_config unset %s gpg-verify-summary; fi' % (i, r, i, r),
        ]

    # Pinned commits are what got installed.
    for remote, refs in remotes.items():
        for ref, commit in sorted(refs.items()):
            lines.append('[ "$(flatpak info --system --show-commit %s)" = %s ] || '
                         '{ echo "vfpk: %s is not at commit %s"; exit 1; }'
                         % (quote(ref), quote(commit), quote(ref), quote(commit)))

    for b in bundles:
        ref = b['refs'][0][0]
        lines += [
            'echo "vfpk: bundle %s"' % quote(b['pn']),
            'flatpak_install --reinstall --bundle "$in/"%s' % quote(b['path']),
        ]
        if not b['allow_no_origin']:
            # A bundle built without --repo-url gets a disabled origin remote
            # with no URL, so the app can never be updated.
            lines.append('origin=$(flatpak info --system --show-origin %s)' % quote(ref))
            lines.append('[ -n "$(remote_config get "$origin" url 2>/dev/null)" ] || '
                         '{ echo "vfpk: %s has no origin URL (built without --repo-url); set '
                         'FLATPAK_BUNDLE_ALLOW_NO_ORIGIN = \\"1\\" in %s to install it anyway"; exit 1; }'
                         % (quote(ref), quote(b['pn'])))

    # flatpak list shortens refs and commits, so ask for each one.
    lines += [
        'out=/var/lib/flatpak/.vfpk-installed.refs',
        ': > "$out"',
        'for kind in app runtime; do',
        '    for ref in $(flatpak list --system --$kind --columns=ref); do',
        '        echo "$kind/$ref $(flatpak info --system --show-origin "$kind/$ref") '
        '$(flatpak info --system --show-commit "$kind/$ref")" >> "$out"',
        '    done',
        'done',
        'cat "$out"',
    ]
    return '\n'.join(lines) + '\n'

def flatpak_autostart_apps(d, bundles):
    """Check BUNDLED_FLATPAKS against what got installed; map PN to the apps to autostart."""
    import re

    entries = {}
    for entry in (d.getVar('BUNDLED_FLATPAKS') or '').split():
        fields = entry.split(':')
        entries[fields[0]] = fields[1:]
    by_pn = {b['pn']: b for b in bundles}

    autostart = {}
    for pn, options in sorted(entries.items()):
        if pn not in by_pn:
            bb.fatal("BUNDLED_FLATPAKS: %s installed no flatpak content into %s; is it a "
                     "flatpak-bundle package for flatpak arch %s?"
                     % (pn, d.getVar('FLATPAK_BUNDLES_DIR'), d.getVar('FLATPAK_ARCH')))
        if 'autostart' not in options:
            continue
        apps = [ref.split('/')[1] for ref, _ in by_pn[pn]['refs'] if ref.startswith('app/')]
        if not apps:
            bb.fatal("BUNDLED_FLATPAKS: %s:autostart, but %s holds no app" % (pn, pn))

        if d.getVarFlag('FLATPAK_SERVICE_FILE', pn):
            if len(apps) != 1:
                bb.fatal("FLATPAK_SERVICE_FILE[%s]: %s holds %d apps; give each its own package"
                         % (pn, pn, len(apps)))
        else:
            user = d.getVarFlag('FLATPAK_APP_USER', pn) or d.getVar('FLATPAK_APP_USER')
            if not user:
                bb.fatal("BUNDLED_FLATPAKS: %s:autostart needs FLATPAK_APP_USER (or "
                         "FLATPAK_APP_USER[%s]); apps are not run as root" % (pn, pn))
            if not re.fullmatch(r'[a-z_][a-z0-9_-]*', user):
                bb.fatal("FLATPAK_APP_USER '%s' is not a user name" % user)
        autostart[pn] = apps
    return autostart

# Runs last among the rootfs post-processing steps, so users created by
# them (extrausers, for one) exist when the unit's user is checked.
python flatpak_autostart_units () {
    import json
    import re

    rootfs = d.getVar('IMAGE_ROOTFS')
    with open(d.getVar('FLATPAK_AUTOSTART')) as f:
        autostart = json.load(f)

    for pn, apps in sorted(autostart.items()):
        custom = d.getVarFlag('FLATPAK_SERVICE_FILE', pn)
        if custom:
            with open(custom) as f:
                units = {apps[0]: f.read()}
        else:
            user = d.getVarFlag('FLATPAK_APP_USER', pn) or d.getVar('FLATPAK_APP_USER')
            with open(os.path.join(rootfs, 'etc', 'passwd')) as f:
                if not any(line.split(':')[0] == user for line in f):
                    bb.fatal("FLATPAK_APP_USER '%s' does not exist in the image" % user)
            env = (d.getVarFlag('FLATPAK_APP_ENV', pn) or d.getVar('FLATPAK_APP_ENV') or '').split()
            for pair in env:
                # Quotes, backslashes and % have meaning in a unit file.
                if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=[^"\\%]*', pair):
                    bb.fatal("FLATPAK_APP_ENV: '%s' is not KEY=VALUE without quotes, \\ or %%" % pair)
            units = {}
            for app in apps:
                units[app] = ''.join([
                    '[Unit]\n',
                    'Description=Flatpak app %s\n' % app,
                    'After=network.target\n',
                    '\n',
                    '[Service]\n',
                    'User=%s\n' % user,
                    ''.join('Environment="%s"\n' % pair for pair in env),
                    'ExecStart=%s/flatpak run --system %s\n' % (d.getVar('bindir'), app),
                    'Restart=on-failure\n',
                    '\n',
                    '[Install]\n',
                    'WantedBy=multi-user.target\n',
                ])

        unitdir = d.getVar('systemd_system_unitdir')
        wants = os.path.join(rootfs + d.getVar('sysconfdir'), 'systemd', 'system', 'multi-user.target.wants')
        bb.utils.mkdirhier(rootfs + unitdir)
        bb.utils.mkdirhier(wants)
        for app, text in units.items():
            name = 'flatpak-app-%s.service' % app
            path = os.path.join(rootfs + unitdir, name)
            with open(path, 'w') as f:
                f.write(text)
            os.chmod(path, 0o644)
            link = os.path.join(wants, name)
            if os.path.lexists(link):
                os.unlink(link)
            os.symlink(os.path.join(unitdir, name), link)
}

FLATPAK_TMP = "${WORKDIR}/vfpk-tmp"
FLATPAK_AUTOSTART = "${WORKDIR}/vfpk-autostart.json"

python flatpak_cross_install () {
    import json
    import math
    import shutil
    from collections import OrderedDict

    rootfs = d.getVar('IMAGE_ROOTFS')
    bundles_dir = rootfs + d.getVar('FLATPAK_BUNDLES_DIR')
    bundles = flatpak_read_bundles(d, bundles_dir)

    # Checked before the guest runs, written after it for the unit step.
    with open(d.getVar('FLATPAK_AUTOSTART'), 'w') as f:
        json.dump(flatpak_autostart_apps(d, bundles), f)

    if not bundles:
        return

    mode = d.getVar('FLATPAK_DEPLOY_MODE')
    if mode != 'rootfs':
        bb.fatal("FLATPAK_DEPLOY_MODE '%s' is not implemented yet; only 'rootfs' is" % mode)
    mc = d.getVar('VFPK_MULTICONFIG')
    if mc not in (d.getVar('BBMULTICONFIG') or '').split():
        bb.fatal("the image installs flatpak content (%s), which needs the vfpk guest: add %s "
                 "to BBMULTICONFIG" % (' '.join(b['pn'] for b in bundles), mc))

    tmp = d.getVar('FLATPAK_TMP')
    stage = os.path.join(tmp, 'stage')
    bb.utils.remove(tmp, recurse=True)
    bb.utils.mkdirhier(stage)

    # One repository per remote, so each remote is switched to a local copy
    # once and every ref of it installs in one transaction.
    remotes = OrderedDict()
    owner = {}
    for b in bundles:
        if b['kind'] != 'repo':
            continue
        refs = remotes.setdefault(b['remote'], OrderedDict())
        for ref, commit in b['refs']:
            if ref in refs and refs[ref] != commit:
                bb.fatal("%s and %s ship %s at different commits" % (owner[ref], b['pn'], ref))
            refs[ref] = commit
            owner[ref] = b['pn']

    remotes_d = os.path.join(rootfs + d.getVar('sysconfdir'), 'flatpak', 'remotes.d')
    for remote in remotes:
        src = os.path.join(remotes_d, remote + '.flatpakrepo')
        if not os.path.isfile(src):
            bb.fatal("flatpak content for remote '%s' (%s), but the image has no %s; add '%s' to "
                     "FLATPAK_REMOTES and flatpak-remotes to the image"
                     % (remote, ' '.join(sorted({owner[r] for r in remotes[remote]})), src, remote))
    # All of them, used or not: see flatpak_guest_script.
    if os.path.isdir(remotes_d):
        shutil.copytree(remotes_d, os.path.join(stage, 'remotes.d'))
    filters = os.path.join(rootfs + d.getVar('sysconfdir'), 'flatpak', 'filters')
    if os.path.isdir(filters):
        shutil.copytree(filters, os.path.join(stage, 'filters'))

    ostree = os.path.join(d.getVar('STAGING_BINDIR_NATIVE'), 'ostree')
    for remote, refs in remotes.items():
        repo = os.path.join(stage, 'repos', remote)
        bb.utils.mkdirhier(repo)
        flatpak_run(d, [ostree, '--repo=%s' % repo, 'init', '--mode=archive'])
        flatpak_run(d, [ostree, '--repo=%s' % repo, 'config', 'set', 'core.min-free-space-size',
                        d.getVar('FLATPAK_REPO_MIN_FREE')])
        for b in bundles:
            if b['kind'] == 'repo' and b['remote'] == remote:
                # Same filesystem and repository mode: objects are hardlinked.
                flatpak_run(d, [ostree, '--repo=%s' % repo, 'pull-local', '--depth=0',
                                os.path.join(bundles_dir, b['path'])] + [ref for ref, _ in b['refs']])
        flatpak_run(d, [ostree, '--repo=%s' % repo, 'summary', '--update'])

    for b in bundles:
        if b['kind'] == 'bundle':
            dest = os.path.join(stage, b['path'])
            bb.utils.mkdirhier(os.path.dirname(dest))
            try:
                os.link(os.path.join(bundles_dir, b['path']), dest)
            except OSError:
                shutil.copy(os.path.join(bundles_dir, b['path']), dest)

    with open(os.path.join(stage, 'install.sh'), 'w') as f:
        f.write(flatpak_guest_script(d, remotes, [b for b in bundles if b['kind'] == 'bundle']))

    installation = rootfs + d.getVar('localstatedir') + '/lib/flatpak'
    storage = os.path.join(tmp, 'storage.tar')
    args = [os.path.join(d.getVar('STAGING_BINDIR_NATIVE'), 'vfpk-runner.sh'),
            '--arch', d.getVar('FLATPAK_ARCH'), '--blob-dir', d.getVar('VFPK_BLOB_DIR'),
            '--input', stage, '--output', storage, '--memory', d.getVar('FLATPAK_INSTALL_MEMORY'),
            '--smp', d.getVar('FLATPAK_INSTALL_SMP')]

    if os.path.isdir(os.path.join(installation, 'repo')):
        # Additive: the guest starts from the installation already there.
        # Archived under pseudo, so the owners are the image's.
        existing = os.path.join(tmp, 'existing.tar')
        flatpak_run(d, ['tar', '--numeric-owner', '-cf', existing, '-C', installation, '.'],
                    unload_pseudo=False)
        args += ['--input-storage', existing]

    timeout = d.getVar('FLATPAK_INSTALL_TIMEOUT')
    if not timeout:
        size = 0
        for top, _, files in os.walk(stage):
            for name in files:
                size += os.lstat(os.path.join(top, name)).st_size
        # Generous: TCG on a loaded builder can be several times slower than KVM.
        timeout = str(900 + 600 * math.ceil(size / (1 << 30)))
    args += ['--timeout', timeout, '--', 'sh "$VFPK_INPUT/install.sh"']

    bb.note("Installing %s in the vfpk guest" % ' '.join(b['pn'] for b in bundles))
    bb.note(flatpak_run(d, args))

    if os.path.lexists(installation):
        bb.utils.remove(installation, recurse=True)
    bb.utils.mkdirhier(installation)
    flatpak_run(d, ['tar', '--numeric-owner', '-xf', storage, '-C', installation], unload_pseudo=False)

    refs_file = rootfs + d.getVar('FLATPAK_INSTALLED_REFS')
    bb.utils.mkdirhier(os.path.dirname(refs_file))
    os.rename(os.path.join(installation, '.vfpk-installed.refs'), refs_file)
    os.chmod(refs_file, 0o644)

    # The bundles are installed; the packages that carried them leave nothing
    # behind in the image.
    bb.utils.remove(bundles_dir, recurse=True)
    bb.utils.remove(tmp, recurse=True)
}
# The guest blobs are a task dependency (mcdepends); their path under TOPDIR
# is not content.
flatpak_cross_install[vardepsexclude] += "BBMULTICONFIG VFPK_BLOB_DIR"
