# meta-flatpak-minimal

OpenEmbedded layer for the [flatpak-minimal](https://github.com/flatpak-minimal)
projects: build-time flatpak installation for Yocto images (vfpk), two
xdg-desktop-portal pieces and two Flutter applications built on the org's Dart
packages.

## Recipes

| Recipe | Upstream | Notes |
| --- | --- | --- |
| `xdg-desktop-portal-agl` | [xdg-desktop-portal-agl](https://github.com/flatpak-minimal/xdg-desktop-portal-agl) | Portal backend implementing Screenshot and Settings on AGL's compositor. Rust. |
| `xdg-portal-settings-minimal` | [xdg-portal-settings-minimal](https://github.com/flatpak-minimal/xdg-portal-settings-minimal) | Standalone `org.freedesktop.impl.portal.Settings` service. Rust. |
| `flatpak-minimal-flatpak-dart-flutter-remote-manager` | [flatpak_dart](https://github.com/flatpak-minimal/flatpak_dart) | Flutter app; needs meta-flutter. |
| `flatpak-minimal-appstream-dart-flathub-catalog` | [appstream_dart](https://github.com/flatpak-minimal/appstream_dart) | Flutter app; needs meta-flutter. |
| `flatpak-remotes` | (this layer) | System flatpak remotes as static `/etc/flatpak/remotes.d` entries. Flathub by default. |
| `flatpak-minimal-image` | (this layer) | Reference image: flatpak plus `flatpak-remotes`. |

The two Flutter recipes live under `dynamic-layers/flutter-layer/` and only
parse when `meta-flutter` is in the build. Everything else needs `openembedded-core`
and `meta-openembedded/meta-oe` only.

Both Flutter recipes were moved here from `meta-flutter/meta-flutter-apps`,
keeping their recipe names. Until the matching meta-flutter change lands, a
build carrying both layers has two providers for each; this layer's
`BBFILE_PRIORITY` is 13 against meta-flutter's 12, so it wins.

## Dependencies

```
URI: git://git.openembedded.org/bitbake               branch: 2.18
URI: git://git.openembedded.org/openembedded-core     branch: wrynose
URI: git://git.openembedded.org/meta-openembedded     branch: wrynose  (meta-oe)
URI: https://github.com/meta-flutter/meta-flutter     branch: wrynose  (optional)
```

`LAYERSERIES_COMPAT` is `wrynose blacksail`. CI builds against wrynose, and
recipe versions this layer relies on (flatpak 1.17.6, ostree 2026.1,
linux-yocto 6.18) are wrynose's. A `wrynose` branch of this layer follows once
CI is green and the image is smoke tested on hardware.

## Adding the layer

```
bitbake-layers add-layer /path/to/meta-flatpak-minimal
```

`xdg-desktop-portal-agl` needs `systemd` and `wayland` in `DISTRO_FEATURES`.
`flatpak-remotes` and `flatpak-minimal-flatpak-dart-flutter-remote-manager`
need `polkit` (inherited from the `flatpak` recipe's own requirement), and
`flatpak-minimal-image` needs `polkit` and `systemd`. Recipes are skipped with
a clear reason when those are missing.

## Portal backends conflict

`xdg-desktop-portal-agl` and `xdg-portal-settings-minimal` both implement the
Settings portal. The AGL backend claims
`org.freedesktop.impl.portal.desktop.agl` and is selected through
`agl-portals.conf`; the minimal service claims
`org.freedesktop.impl.portal.Settings` directly. Install one or the other, not
both.

`xdg-portal-settings-minimal` ships no D-Bus service file and no systemd unit
upstream, so nothing starts it automatically.

## vfpk: flatpak apps installed at build time

vfpk produces an image whose flatpak apps are already installed, with their
remotes configured so `flatpak update` works in the field. It follows the
design of meta-virtualization's vcontainer without depending on it: the build
boots a QEMU guest of the target architecture that runs the target's own
flatpak, installs the requested refs into a system installation
(`/var/lib/flatpak`), and hands the result back to the image.

The work is in progress. `classes/flatpak-common.bbclass` holds the
per-architecture guest table (aarch64, x86-64, riscv64 and 32-bit arm) and the
deploy mode:

| `FLATPAK_DEPLOY_MODE` | Where the installation goes |
| --- | --- |
| `rootfs` | Unpacked into the rootfs. Default for a writable rootfs; refused with `read-only-rootfs`. |
| `partition` | An ext4 image placed by wic as the partition mounted at `/var/lib/flatpak`. Default with `read-only-rootfs`. |
| `seed` | A tar in the rootfs, unpacked into the writable `/var/lib/flatpak` on first boot. |

## Remotes

`flatpak-remotes` writes one `/etc/flatpak/remotes.d/<name>.flatpakrepo` per
name in `FLATPAK_REMOTES` (default `flathub`). Each remote is described by
varflags:

```
FLATPAK_REMOTES = "flathub acme"
FLATPAK_REMOTE_URL[acme] = "https://flatpak.acme.example/repo/"
FLATPAK_REMOTE_TITLE[acme] = "Acme"
FLATPAK_REMOTE_GPGKEY[acme] = "acme.gpg"
FLATPAK_REMOTE_COLLECTION_ID[acme] = "com.acme.Apps"
FLATPAK_REMOTE_FILTER[acme] = "acme.filter"
```

`FLATPAK_REMOTE_GPGKEY` and `FLATPAK_REMOTE_FILTER` name files in the recipe's
search path, so add them from a `flatpak-remotes.bbappend` with
`FILESEXTRAPATHS`. The key must be binary (`gpg --export KEYID`), not ASCII
armored. A remote without a key is refused unless
`FLATPAK_REMOTE_NO_GPG[name] = "1"`.

flatpak applies a remotes.d file once, the first time it opens the system
installation, and only if no remote of that name exists yet. There is no
default remote: an installed app is updated from the remote it was installed
from, and `flatpak install` without a remote searches all of them.

The bundled Flathub key (`6E5C05D979C76DAF93C081354184DD4D907A7CAE`) expires
on 2027-06-14; refresh `recipes-core/flatpak-remotes/files/flathub.gpg` from
`https://dl.flathub.org/repo/flathub.flatpakrepo` before then.

## Maintenance

Rust crate lists are generated, not hand written:

```
bitbake -c update_crates xdg-desktop-portal-agl
bitbake -c update_crates xdg-portal-settings-minimal
```

The vendored pub cache for `flatpak-minimal-appstream-dart-flathub-catalog`
(`*-pubcache.inc` and `*-pubspec.lock`) is generated by meta-flutter's
`tools/pubvendor/pubvendor.py`.

## Contributing

Send patches as pull requests to
<https://github.com/flatpak-minimal/meta-flatpak-minimal>. Every commit needs
a `Signed-off-by:` line (the Developer Certificate of Origin, `git commit -s`).
Run `shellcheck` on shell scripts and `oelint-adv` on recipes and classes
before sending.

Security issues: see [SECURITY.md](SECURITY.md).

## Maintainers

Joel Winarske <joel.winarske@linux.com>

## License

MIT. See [LICENSE](LICENSE). Recipes carry the license of the software they
build, which is not MIT in every case.
