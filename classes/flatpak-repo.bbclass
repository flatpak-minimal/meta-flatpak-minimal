#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Helpers for committing flatpak refs built by this build into ostree
# repositories, shared by flatpak-runtime-image and flatpak-app.
#
# A ref is a tree with a 'metadata' keyfile and a 'files' directory,
# committed with ostree-native the way 'flatpak build-export' would: owned by
# root, without setuid bits or xattrs, bound to its ref and carrying the
# metadata in xa.metadata, byte for byte. Commits are timestamped with
# SOURCE_DATE_EPOCH, so the same input gives the same commit.
#
# FLATPAK_GPGID signs the commits with that key from FLATPAK_GPGHOME (a GnuPG
# home directory). Signed commits install from a remote that verifies them;
# unsigned ones need a remote with FLATPAK_REMOTE_NO_GPG set in
# flatpak-remotes.
#
# FLATPAK_BUILD_REMOTE names the remote refs built here install under, and so
# the remote devices update them from. Publish the repositories this build
# deploys there.

inherit flatpak-common

FLATPAK_GPGID ??= ""
FLATPAK_GPGHOME ??= ""
FLATPAK_BUILD_REMOTE ??= ""

FLATPAK_ID_RE = "[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*){2,}"
FLATPAK_BRANCH_RE = "[A-Za-z0-9_][A-Za-z0-9_.-]*"

DEPENDS += "ostree-native ${@'gnupg-native' if d.getVar('FLATPAK_GPGID') else ''}"

def flatpak_repo_check_signing(d):
    if d.getVar('FLATPAK_GPGID') and not os.path.isdir(d.getVar('FLATPAK_GPGHOME') or ''):
        bb.fatal("FLATPAK_GPGID is set, but FLATPAK_GPGHOME '%s' is not a GnuPG home directory"
                 % d.getVar('FLATPAK_GPGHOME'))

def flatpak_repo_ostree(d, args):
    import subprocess
    env = dict(os.environ)
    env['PATH'] = '%s:%s:%s' % (d.getVar('STAGING_BINDIR_NATIVE'), d.getVar('STAGING_SBINDIR_NATIVE'),
                                env.get('PATH', ''))
    # The repository is outside any pseudo-tracked tree.
    env['PSEUDO_UNLOAD'] = '1'
    proc = subprocess.run([os.path.join(d.getVar('STAGING_BINDIR_NATIVE'), 'ostree')] + args,
                          env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if proc.returncode != 0:
        bb.fatal("ostree %s failed:\n%s" % (' '.join(args), proc.stdout))
    return proc.stdout

def flatpak_repo_finish_args(d, args):
    """Turn flatpak-builder style finish-args into metadata keyfile groups."""
    import re

    lists = {'shared': [], 'sockets': [], 'devices': [], 'features': [],
             'filesystems': [], 'persistent': []}
    groups = {'Environment': [], 'Session Bus Policy': [], 'System Bus Policy': []}
    flags = {
        'share': ('shared', ''), 'unshare': ('shared', '!'),
        'socket': ('sockets', ''), 'nosocket': ('sockets', '!'),
        'device': ('devices', ''), 'nodevice': ('devices', '!'),
        'allow': ('features', ''), 'disallow': ('features', '!'),
        'filesystem': ('filesystems', ''), 'nofilesystem': ('filesystems', '!'),
        'persist': ('persistent', ''),
    }
    bus = {
        'talk-name': ('Session Bus Policy', 'talk'), 'own-name': ('Session Bus Policy', 'own'),
        'see-name': ('Session Bus Policy', 'see'),
        'system-talk-name': ('System Bus Policy', 'talk'), 'system-own-name': ('System Bus Policy', 'own'),
        'system-see-name': ('System Bus Policy', 'see'),
    }
    for arg in args.split():
        m = re.fullmatch(r'--([a-z-]+)=(.+)', arg)
        if not m:
            bb.fatal("finish arg '%s' is not --OPTION=VALUE" % arg)
        option, value = m.groups()
        # Values become keyfile entries; ';' separates list items there.
        if re.search(r'[;\[\]\s]', value) or '\\' in value:
            bb.fatal("finish arg '%s' has a value flatpak metadata cannot hold" % arg)
        if option in flags:
            key, prefix = flags[option]
            lists[key].append(prefix + value)
        elif option in bus:
            group, policy = bus[option]
            groups[group].append('%s=%s' % (value, policy))
        elif option == 'env':
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', value):
                bb.fatal("finish arg '%s' is not --env=KEY=VALUE" % arg)
            groups['Environment'].append(value)
        else:
            bb.fatal("finish arg '--%s' is not supported" % option)

    text = ''
    context = ['%s=%s;' % (key, ';'.join(values)) for key, values in lists.items() if values]
    if context:
        text += '\n[Context]\n' + '\n'.join(context) + '\n'
    for group, entries in groups.items():
        if entries:
            text += '\n[%s]\n' % group + '\n'.join(entries) + '\n'
    return text

def flatpak_repo_commit(d, repo, ref, tree, subject):
    """Commit TREE (with TREE/metadata and TREE/files) as REF into the archive repository REPO."""
    flatpak_repo_check_signing(d)
    if not os.path.exists(os.path.join(repo, 'config')):
        bb.utils.mkdirhier(repo)
        flatpak_repo_ostree(d, ['--repo=%s' % repo, 'init', '--mode=archive'])
    flatpak_repo_ostree(d, ['--repo=%s' % repo, 'config', 'set', 'core.min-free-space-size',
                            d.getVar('FLATPAK_REPO_MIN_FREE')])
    with open(os.path.join(tree, 'metadata')) as f:
        metadata = f.read()

    args = ['--repo=%s' % repo, 'commit', '--branch=%s' % ref, '--tree=dir=%s' % tree,
            '--subject=%s' % subject, '--canonical-permissions', '--no-xattrs',
            '--add-metadata-string=xa.metadata=%s' % metadata]
    epoch = d.getVar('SOURCE_DATE_EPOCH')
    if epoch:
        args.append('--timestamp=@%s' % epoch)
    if d.getVar('FLATPAK_GPGID'):
        args += ['--gpg-sign=%s' % d.getVar('FLATPAK_GPGID'), '--gpg-homedir=%s' % d.getVar('FLATPAK_GPGHOME')]
    flatpak_repo_ostree(d, args)
    flatpak_repo_ostree(d, ['--repo=%s' % repo, 'summary', '--update'])
    return flatpak_repo_ostree(d, ['--repo=%s' % repo, 'rev-parse', ref]).strip()
