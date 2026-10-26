#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Install flatpak content at build time. System scope uses /var/lib/flatpak;
# user scope seeds the installation into FLATPAK_INSTALL_USER's home on boot.
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
#              the package. The unit runs 'flatpak run --<scope> <ID>' as
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
# line, in ${FLATPAK_INSTALLED_REFS} for launchers. It records what the build
# installed; on a device that has updated since, flatpak itself is current.
#
# Where the installation goes follows FLATPAK_DEPLOY_MODE (flatpak-common):
#
#   rootfs     ${localstatedir}/lib/flatpak in the rootfs.
#   partition  an ext4 image deployed as ${IMAGE_LINK_NAME}.vfpk-data.ext4
#              (FLATPAK_DATA_IMAGE), labeled FLATPAK_DATA_LABEL, with room
#              for FLATPAK_DATA_EXTRA_SPACE MB of updates or a fixed
#              FLATPAK_DATA_SIZE MB. Place it as the partition mounted at
#              /var/lib/flatpak, e.g. from a .wks.in:
#                part /var/lib/flatpak --source rawcopy --fstype=ext4 --no-fstab-update
#                     --sourceparams="file=${FLATPAK_DATA_IMAGE}" --label flatpak
#              It is built even without flatpak content, so the layout holds.
#   seed       a tar at ${FLATPAK_SEED}, unpacked into the writable
#              /var/lib/flatpak on first boot by vfpk-seed.service, which
#              the class adds to the image. It never unpacks over an
#              existing installation, so updates made in the field survive
#              an OS update that brings a newer seed.
#
# In partition and seed modes the rootfs keeps an empty /var/lib/flatpak as
# the mount point, and FLATPAK_DATA_FSTAB (for partition, a mount of the
# FLATPAK_DATA_LABEL filesystem) is added to /etc/fstab. Seed mode on a
# read-only rootfs needs that mount too: without persistent storage at
# /var/lib/flatpak the seed lands in RAM and is unpacked again every boot.
#
# Needs the vfpk-<arch> multiconfig for the image's architecture in
# BBMULTICONFIG (see conf/multiconfig). An image without flatpak content
# builds without it.

inherit flatpak-common

BUNDLED_FLATPAKS ??= ""

FLATPAK_APP_USER ??= ""
FLATPAK_APP_ENV ??= ""

FLATPAK_INSTALLED_REFS = "${datadir}/vfpk/installed.refs"
FLATPAK_INSTALLED_SCOPE = "${datadir}/vfpk/installed.scope"

FLATPAK_DATA_IMAGE = "${IMGDEPLOYDIR}/${IMAGE_NAME}.vfpk-data.ext4"
FLATPAK_DATA_LABEL ??= "flatpak"
FLATPAK_DATA_EXTRA_SPACE ??= "1024"
FLATPAK_DATA_SIZE ??= ""
# Empty derives a fixed UUID from the image name and machine.
FLATPAK_DATA_UUID ??= ""
# On a read-only rootfs, volatile-binds makes ${localstatedir}/lib writable
# with an overlay or a tmpfs copy mounted over it. Mounted first, the data
# partition ends up underneath, and flatpak writes to a copy in RAM that is
# gone at the next boot, so mount it after. Ordering against a unit that does
# not exist is a no-op.
FLATPAK_DATA_FSTAB_OPTIONS ??= "defaults,x-systemd.after=var-volatile-lib.service"
FLATPAK_DATA_FSTAB ??= "${@'LABEL=%s %s/lib/flatpak ext4 %s 0 2' % (d.getVar('FLATPAK_DATA_LABEL'), d.getVar('localstatedir'), d.getVar('FLATPAK_DATA_FSTAB_OPTIONS')) if d.getVar('FLATPAK_DEPLOY_MODE') == 'partition' else ''}"
FLATPAK_SEED = "${datadir}/vfpk/seed.tar"

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

    mode = d.getVar('FLATPAK_DEPLOY_MODE')
    if mode == 'seed':
        if not bb.utils.contains('DISTRO_FEATURES', 'systemd', True, False, d):
            bb.fatal("FLATPAK_DEPLOY_MODE = \"seed\" needs systemd in DISTRO_FEATURES for vfpk-seed.service")
        d.appendVar('IMAGE_INSTALL', ' vfpk-seed')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,16}', d.getVar('FLATPAK_DATA_LABEL') or ''):
        bb.fatal("FLATPAK_DATA_LABEL '%s' is not an ext4 label (up to 16 of A-Z a-z 0-9 _ -)"
                 % d.getVar('FLATPAK_DATA_LABEL'))
    for var in ('FLATPAK_DATA_EXTRA_SPACE', 'FLATPAK_DATA_SIZE'):
        if not re.fullmatch(r'[0-9]*', d.getVar(var) or ''):
            bb.fatal("%s must be a number of MB" % var)
    if '\n' in (d.getVar('FLATPAK_DATA_FSTAB') or ''):
        bb.fatal("FLATPAK_DATA_FSTAB must be one fstab line")

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

do_rootfs[vardeps] += "BUNDLED_FLATPAKS FLATPAK_DEPLOY_MODE FLATPAK_INSTALL_SCOPE FLATPAK_INSTALL_USER FLATPAK_APP_USER FLATPAK_APP_ENV \
    FLATPAK_SERVICE_FILE FLATPAK_INSTALL_TIMEOUT FLATPAK_INSTALL_MEMORY FLATPAK_DATA_LABEL \
    FLATPAK_DATA_EXTRA_SPACE FLATPAK_DATA_SIZE FLATPAK_DATA_UUID FLATPAK_DATA_FSTAB FLATPAK_SEED"
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
        'scope=%s' % quote(d.getVar('FLATPAK_INSTALL_SCOPE')),
        # The runner archives /var/lib/flatpak regardless of installation scope.
        'if [ "$scope" = user ]; then export FLATPAK_USER_DIR=/var/lib/flatpak; fi',
        'repo=/var/lib/flatpak/repo',
        'in=$VFPK_INPUT',
        'flatpak_install() { flatpak install --"$scope" -y --noninteractive "$@"; }',
        'remote_config() { ostree --repo="$repo" config "$1" "remote \\"$2\\".$3" ${4:+"$4"}; }',
        # Filters are referenced by absolute path from the .flatpakrepo files.
        'if [ -d "$in/filters" ]; then mkdir -p /etc/flatpak/filters && cp "$in"/filters/* /etc/flatpak/filters/; fi',
        # The image's remotes.d, applied by flatpak itself the first time it
        # opens the installation, as on the device: each file becomes a
        # remote unless one of that name exists, and is recorded as applied.
        # One left unapplied would make the first unprivileged flatpak
        # command on the device need root to apply it.
        'if [ -d "$in/remotes.d" ]; then mkdir -p /etc/flatpak/remotes.d && cp "$in"/remotes.d/* /etc/flatpak/remotes.d/; fi',
        # remotes.d only populates system installations. Import the same files
        # explicitly for a user installation, including their keys and filters.
        'if [ "$scope" = user ]; then',
        '    for config in /etc/flatpak/remotes.d/*.flatpakrepo; do',
        '        [ -f "$config" ] || continue',
        '        remote=${config##*/}; remote=${remote%.flatpakrepo}',
        '        flatpak remote-add --user --if-not-exists "$remote" "$config"',
        '    done',
        'fi',
        'flatpak remotes --"$scope" --show-disabled --columns=name > /tmp/remotes',
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
            'flatpak remote-modify --"$scope" --url="file://$in/repos/"%s %s' % (r, r),
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
            'flatpak remote-modify --"$scope" --url="$url_%d" %s' % (i, r),
            'if [ -n "$gvs_%d" ]; then remote_config set %s gpg-verify-summary "$gvs_%d"; '
            'else remote_config unset %s gpg-verify-summary; fi' % (i, r, i, r),
        ]

    # Pinned commits are what got installed.
    for remote, refs in remotes.items():
        for ref, commit in sorted(refs.items()):
            lines.append('[ "$(flatpak info --"$scope" --show-commit %s)" = %s ] || '
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
            lines.append('origin=$(flatpak info --"$scope" --show-origin %s)' % quote(ref))
            lines.append('[ -n "$(remote_config get "$origin" url 2>/dev/null)" ] || '
                         '{ echo "vfpk: %s has no origin URL (built without --repo-url); set '
                         'FLATPAK_BUNDLE_ALLOW_NO_ORIGIN = \\"1\\" in %s to install it anyway"; exit 1; }'
                         % (quote(ref), quote(b['pn'])))

    # flatpak list shortens refs and commits, so ask for each one. The list
    # goes to the output, not into the installation.
    lines += [
        'echo "===VFPK_REFS_BEGIN==="',
        'for kind in app runtime; do',
        '    for ref in $(flatpak list --"$scope" --$kind --columns=ref); do',
        '        echo "$kind/$ref $(flatpak info --"$scope" --show-origin "$kind/$ref") '
        '$(flatpak info --"$scope" --show-commit "$kind/$ref")"',
        '    done',
        'done',
        'echo "===VFPK_REFS_END==="',
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
            user = flatpak_app_user(d, pn)
            if not user:
                bb.fatal("BUNDLED_FLATPAKS: %s:autostart needs FLATPAK_APP_USER (or "
                         "FLATPAK_APP_USER[%s]); apps are not run as root" % (pn, pn))
            if not re.fullmatch(r'[a-z_][a-z0-9_-]*', user) or user == 'root':
                bb.fatal("FLATPAK_APP_USER '%s' must be a non-root user name" % user)
            if d.getVar('FLATPAK_INSTALL_SCOPE') == 'user' and user != d.getVar('FLATPAK_INSTALL_USER'):
                bb.fatal("FLATPAK_APP_USER for %s must match FLATPAK_INSTALL_USER for a user installation" % pn)
        autostart[pn] = apps
    return autostart

def flatpak_app_user(d, pn):
    return (d.getVarFlag('FLATPAK_APP_USER', pn) or d.getVar('FLATPAK_APP_USER') or
            (d.getVar('FLATPAK_INSTALL_USER') if d.getVar('FLATPAK_INSTALL_SCOPE') == 'user' else ''))

def flatpak_user_account(d, user):
    """Resolve the target account after extrausers has populated passwd."""
    import re
    with open(os.path.join(d.getVar('IMAGE_ROOTFS'), 'etc', 'passwd')) as f:
        fields = next((line.rstrip('\n').split(':') for line in f if line.split(':')[0] == user), None)
    if not fields:
        bb.fatal("Flatpak user '%s' does not exist in the image" % user)
    uid, gid, home = int(fields[2]), int(fields[3]), fields[5]
    # These values become systemd paths and Environment entries.
    if uid == 0 or not re.fullmatch(r'/[A-Za-z0-9_./-]+', home) or os.path.normpath(home) != home:
        bb.fatal("Flatpak user '%s' needs a non-zero UID and an absolute home without spaces or systemd specifiers" % user)
    return uid, gid, home

def flatpak_user_seed_unit(d):
    """Seed as the owner, so tar creates every file with the account's UID/GID."""
    user = d.getVar('FLATPAK_INSTALL_USER')
    _, _, home = flatpak_user_account(d, user)
    directory = home + '/.local/share/flatpak'
    return ''.join([
        '[Unit]\n',
        'Description=Seed Flatpak apps for %s\n' % user,
        'DefaultDependencies=no\n',
        'RequiresMountsFor=%s\n' % home,
        'After=local-fs.target\n',
        'Before=sysinit.target systemd-user-sessions.service\n',
        'ConditionPathExists=%s\n' % d.getVar('FLATPAK_SEED'),
        'ConditionPathExists=!%s/.vfpk-seeded\n' % directory,
        '\n[Service]\n',
        'Type=oneshot\nRemainAfterExit=yes\n',
        'User=%s\n' % user,
        'Environment=HOME=%s\n' % home,
        'Environment=VFPK_SEED_DIR=%s\n' % directory,
        'ExecStart=%s/vfpk-seed\n' % d.getVar('libexecdir'),
        '\n[Install]\nWantedBy=sysinit.target\n',
    ])

# Runs last among the rootfs post-processing steps, so users created by
# them (extrausers, for one) exist when the unit's user is checked.
python flatpak_autostart_units () {
    import json
    import re

    rootfs = d.getVar('IMAGE_ROOTFS')
    with open(d.getVar('FLATPAK_AUTOSTART')) as f:
        autostart = json.load(f)

    if d.getVar('FLATPAK_INSTALL_SCOPE') == 'user':
        path = rootfs + d.getVar('systemd_system_unitdir') + '/vfpk-seed.service'
        with open(path, 'w') as f:
            f.write(flatpak_user_seed_unit(d))

    for pn, apps in sorted(autostart.items()):
        custom = d.getVarFlag('FLATPAK_SERVICE_FILE', pn)
        if custom:
            with open(custom) as f:
                units = {apps[0]: f.read()}
        else:
            user = flatpak_app_user(d, pn)
            uid, gid, home = flatpak_user_account(d, user)
            scope = d.getVar('FLATPAK_INSTALL_SCOPE')
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
                    'Requires=user@%d.service\nAfter=user@%d.service\n' % (uid, uid),
                    'Requires=vfpk-seed.service\nAfter=vfpk-seed.service\n' if d.getVar('FLATPAK_DEPLOY_MODE') == 'seed' else '',
                    '\n',
                    '[Service]\n',
                    'User=%s\n' % user,
                    'Environment=HOME=%s\n' % home,
                    'Environment=XDG_RUNTIME_DIR=/run/user/%d\n' % uid,
                    'Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%d/bus\n' % uid,
                    ''.join('Environment="%s"\n' % pair for pair in env),
                    'ExecStart=%s/flatpak run --%s %s\n' % (d.getVar('bindir'), scope, app),
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

def flatpak_installed_refs(d, output):
    """The guest's list of installed refs, checked line by line."""
    import re
    lines = output.splitlines()
    try:
        begin = lines.index('===VFPK_REFS_BEGIN===')
        end = lines.index('===VFPK_REFS_END===', begin)
    except ValueError:
        bb.fatal("the vfpk guest reported no list of installed refs")
    refs = lines[begin + 1:end]
    for line in refs:
        if not re.fullmatch(r'%s %s [0-9a-f]{64}' % (d.getVar('FLATPAK_REF_RE'), d.getVar('FLATPAK_NAME_RE')), line):
            bb.fatal("the vfpk guest reported a bad installed ref: '%s'" % line)
    return refs

def flatpak_make_data_image(d, tree):
    """Build the ext4 partition image of FLATPAK_DEPLOY_MODE = "partition" from TREE."""
    import math
    import uuid

    image = d.getVar('FLATPAK_DATA_IMAGE')
    # Every file and directory takes whole blocks; ostree repositories hold
    # many small files.
    used = 0
    for top, dirs, names in os.walk(tree):
        for name in dirs + names:
            used += max(4096, math.ceil(os.lstat(os.path.join(top, name)).st_size / 4096) * 4096)
    size_mb = math.ceil(used * 1.25 / (1 << 20)) + 128 + int(d.getVar('FLATPAK_DATA_EXTRA_SPACE'))
    size = d.getVar('FLATPAK_DATA_SIZE')
    if size:
        if int(size) < size_mb - int(d.getVar('FLATPAK_DATA_EXTRA_SPACE')):
            bb.fatal("FLATPAK_DATA_SIZE %s MB is too small for the installation (%d MB)"
                     % (size, size_mb - int(d.getVar('FLATPAK_DATA_EXTRA_SPACE'))))
        size_mb = int(size)

    # Same input, same image: fixed UUID, hash seed and timestamps.
    fs_uuid = d.getVar('FLATPAK_DATA_UUID') or \
        str(uuid.uuid5(uuid.NAMESPACE_URL, 'vfpk-data:%s:%s' % (d.getVar('PN'), d.getVar('MACHINE'))))
    epoch = d.getVar('SOURCE_DATE_EPOCH') or '0'
    bb.utils.remove(image)
    # Under pseudo: mke2fs records the image's owners, not the build user's.
    flatpak_run(d, ['env', 'E2FSPROGS_FAKE_TIME=%s' % epoch, 'SOURCE_DATE_EPOCH=%s' % epoch,
                    'mke2fs', '-q', '-F', '-t', 'ext4', '-i', '4096', '-m', '0',
                    '-L', d.getVar('FLATPAK_DATA_LABEL'), '-U', fs_uuid,
                    '-E', 'hash_seed=%s,root_owner=0:0' % fs_uuid,
                    '-d', tree, image, '%dM' % size_mb], unload_pseudo=False)
    flatpak_run(d, ['e2fsck', '-fn', image], unload_pseudo=False)
    link = d.getVar('IMAGE_LINK_NAME')
    if link:
        path = os.path.join(d.getVar('IMGDEPLOYDIR'), link + '.vfpk-data.ext4')
        if os.path.lexists(path):
            os.unlink(path)
        os.symlink(os.path.basename(image), path)
    bb.note("Built %s (%d MB, label %s)" % (image, size_mb, d.getVar('FLATPAK_DATA_LABEL')))

def flatpak_deploy(d, installation):
    """Move the installation in the rootfs where FLATPAK_DEPLOY_MODE says."""
    rootfs = d.getVar('IMAGE_ROOTFS')
    mode = d.getVar('FLATPAK_DEPLOY_MODE')
    bb.utils.mkdirhier(installation)
    if mode == 'partition':
        flatpak_make_data_image(d, installation)
    elif mode == 'seed' and os.listdir(installation):
        seed = rootfs + d.getVar('FLATPAK_SEED')
        bb.utils.mkdirhier(os.path.dirname(seed))
        flatpak_run(d, ['tar', '--numeric-owner', '-cf', seed, '-C', installation, '.'], unload_pseudo=False)
        os.chmod(seed, 0o644)
    if mode != 'rootfs':
        # Left as the mount point of the writable storage.
        bb.utils.remove(installation, recurse=True)
        bb.utils.mkdirhier(installation)

    entry = d.getVar('FLATPAK_DATA_FSTAB')
    if entry:
        with open(os.path.join(rootfs + d.getVar('sysconfdir'), 'fstab'), 'a') as f:
            f.write(entry + '\n')

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

    installation = rootfs + d.getVar('localstatedir') + '/lib/flatpak'
    if not bundles:
        # A partition layout expects its partition whether or not anything
        # was installed.
        flatpak_deploy(d, installation)
        return

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
    output = flatpak_run(d, args)
    bb.note(output)
    installed = flatpak_installed_refs(d, output)

    if os.path.lexists(installation):
        bb.utils.remove(installation, recurse=True)
    bb.utils.mkdirhier(installation)
    flatpak_run(d, ['tar', '--numeric-owner', '-xf', storage, '-C', installation], unload_pseudo=False)
    bb.utils.remove(storage)
    flatpak_deploy(d, installation)

    refs_file = rootfs + d.getVar('FLATPAK_INSTALLED_REFS')
    bb.utils.mkdirhier(os.path.dirname(refs_file))
    with open(refs_file, 'w') as f:
        f.write(''.join(line + '\n' for line in installed))
    os.chmod(refs_file, 0o644)
    with open(rootfs + d.getVar('FLATPAK_INSTALLED_SCOPE'), 'w') as f:
        f.write(d.getVar('FLATPAK_INSTALL_SCOPE') +
                (' ' + d.getVar('FLATPAK_INSTALL_USER') if d.getVar('FLATPAK_INSTALL_SCOPE') == 'user' else '') + '\n')

    # The bundles are installed; the packages that carried them leave nothing
    # behind in the image.
    bb.utils.remove(bundles_dir, recurse=True)
    bb.utils.remove(tmp, recurse=True)
}
# The guest blobs are a task dependency (mcdepends); their path under TOPDIR
# is not content.
flatpak_cross_install[vardepsexclude] += "BBMULTICONFIG VFPK_BLOB_DIR"
