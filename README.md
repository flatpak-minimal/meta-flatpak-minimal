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
| `vfpk-seed` | (this layer) | First-boot unpacker for `FLATPAK_DEPLOY_MODE = "seed"`; added by `flatpak-cross-install`. |
| `flatpak-minimal-image` | (this layer) | Reference image: flatpak plus `flatpak-remotes`; installs `BUNDLED_FLATPAKS` at build time. |

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

### The guest

The guest is built by its own distro, `vfpk`, through one multiconfig per
architecture:

```
BBMULTICONFIG = "vfpk-aarch64 vfpk-x86-64 vfpk-riscv64 vfpk-arm"
```

Only the entry for the image's own architecture is needed. Each multiconfig
has its own `TMPDIR` (`tmp-vfpk-<arch>`) and builds a kernel, a tiny initramfs
and a squashfs root filesystem with flatpak, ostree and bubblewrap;
`vfpk-initramfs-create` collects them into
`tmp-vfpk-<arch>/deploy/images/<machine>/vfpk/<arch>/`. In the guest, flatpak
is built without its polkit system helper: it runs as root and never needs
it. Nothing in the `vfpk` distro changes other builds.

`vfpk-runner.sh`, installed by `vfpk-native`, boots that guest with QEMU (KVM
when the guest is the host's own architecture, TCG otherwise), runs one
command as root and collects `/var/lib/flatpak` as a tar. All exchange with
the guest goes through virtio disks, so QEMU needs no virtfs support. A boot
takes a few seconds even under TCG.

```
bitbake mc:vfpk-aarch64:vfpk-initramfs-create vfpk-native
vfpk-runner.sh --arch aarch64 \
    --blob-dir tmp-vfpk-aarch64/deploy/images/qemuarm64/vfpk/aarch64 \
    --input DIR --output installation.tar -- 'flatpak install --system ...'
```

### vfpk on a development host

`vfpk` keeps a flatpak system installation for a target architecture in a tar
and runs flatpak on it in the guest, one boot per command. It is installed by
`vfpk-native` next to the runner, and `vfpk-tarball` packages it as a
standalone installer with the guest blobs of one architecture and its own QEMU
and mke2fs:

```
bitbake mc:vfpk-aarch64:vfpk-tarball
./tmp-vfpk-aarch64/deploy/sdk/vfpk-standalone-x86_64-aarch64.sh -d ~/vfpk -y
. ~/vfpk/environment-setup-x86_64-oesdk-linux

vfpk install tmp/deploy/flatpak/repo-dev org.flatpak_minimal.Platform//wrynose
vfpk install app.flatpak
vfpk --network flatpak remote-add flathub https://dl.flathub.org/repo/flathub.flatpakrepo
vfpk flatpak list
vfpk run org.example.Tool --version
```

The installation is `~/.local/share/vfpk/<arch>/flatpak.tar` (`--state`), with
numeric owners. A command that fails leaves it as it was. Unpacked as root
into `/var/lib/flatpak` on a device of the same architecture, it is the
installation built here. `vfpk run` has no display, so it suits command-line
tools and tests, not GUI apps.

From a build tree, point vfpk at the blobs instead:

```
bitbake vfpk-native -caddto_recipe_sysroot
oe-run-native vfpk-native vfpk \
    --blob-dir tmp-vfpk-aarch64/deploy/images/qemuarm64/vfpk/aarch64 flatpak list
```

### Flatpak content from outside the build

`classes/flatpak-bundle.bbclass` packages flatpak content built elsewhere, so
it can be installed at build time. A recipe provides either refs mirrored
from a remote, pinned by commit:

```
inherit flatpak-bundle
FLATPAK_REMOTE = "flathub"
FLATPAK_REMOTE_URL = "https://dl.flathub.org/repo/"
FLATPAK_REMOTE_GPGKEY = "flathub.gpg"
FLATPAK_REMOTE_REFS:aarch64 = "runtime/org.freedesktop.Platform/aarch64/25.08@<commit>"
```

or a single `.flatpak` bundle (`FLATPAK_BUNDLE_FILE`, `FLATPAK_BUNDLE_REF`)
fetched through `SRC_URI` with a checksum. Mirrored commits are pulled with
ostree-native into `${DL_DIR}/flatpak-mirror` during `do_fetch`, checked
against the GPG key and against the ref each commit is bound to, and shipped
in the package as an ostree repository. Find a commit to pin with
`flatpak remote-info flathub <ref>`; Flathub's summary only lists x86_64 refs
for plain ostree, so the build pulls by commit, never by name.

A bundle should be built with `flatpak build-bundle --repo-url=...` so the
installed app can be updated from that remote; it installs under that origin,
so `FLATPAK_REMOTE` does not apply to it. One without it installs but never
updates, and has to be allowed explicitly with
`FLATPAK_BUNDLE_ALLOW_NO_ORIGIN = "1"`.

The layer ships two such recipes, for aarch64 and x86_64:

| Recipe | Content |
| --- | --- |
| `flathub-freedesktop-platform` | `org.freedesktop.Platform` and its `GL.default` extension, 25.08, pinned |
| `flutter-remote-manager` | the released `flutter_remote_manager` bundle; built without `--repo-url`, so not updatable |

The Freedesktop runtime is an aggregate of hundreds of components that this
build neither builds nor inspects, and its manifest does not carry their
licenses, so they cannot be listed or checked against `INCOMPATIBLE_LICENSE`.
The recipe's license text says where they are recorded, and the recipe is
restricted: accept that explicitly with `LICENSE_FLAGS_ACCEPTED += "flathub"`
(which `flutter-remote-manager`, built on it, needs too).

### Installing flatpak content into an image

An image that inherits `flatpak-cross-install` gets every flatpak-bundle
package it installs put into its system installation at build time:

```
inherit flatpak-cross-install
BUNDLED_FLATPAKS = "flathub-freedesktop-platform flutter-remote-manager"
```

`BUNDLED_FLATPAKS` adds the packages to `IMAGE_INSTALL`; listing them in
`IMAGE_INSTALL` directly works too. After the rootfs is assembled, the class
collects what the packages put under `/usr/share/flatpak-bundles`, boots the
guest, installs it with flatpak and unpacks the resulting installation into
`/var/lib/flatpak`. The bundle files themselves do not stay in the image.

- Mirrored refs install under their remote's real name, from a local copy
  that is then swapped back for the remote's real URL. The remote's
  configuration is the image's own `/etc/flatpak/remotes.d` entry, so the
  remote must be in `FLATPAK_REMOTES`, and every installed ref has it as its
  origin: `flatpak update` works on the device. Commit signatures are checked
  against the remote's key, and each ref must end up at its pinned commit.
- A bundle installs under the origin remote it was built with, and fails the
  build if it has none, unless its recipe allows that.
- An installation already in the rootfs is kept and added to.
- `/usr/share/vfpk/installed.refs` lists every installed ref with its origin
  and commit, for launchers that should not have to query flatpak.

Options follow the package name, separated by colons:

| Option | Effect |
| --- | --- |
| `autostart` | Generate and enable `flatpak-app-<ID>.service` for each app in the package. It runs `flatpak run --<scope> <ID>` as `FLATPAK_APP_USER` (required for system scope; user scope defaults to the install account; `FLATPAK_APP_USER[pn]` overrides it), with the `KEY=VALUE` pairs of `FLATPAK_APP_ENV`. `FLATPAK_SERVICE_FILE[pn]`, an absolute path, replaces the generated unit. Needs systemd. |
| `external` | Do not add the package to `IMAGE_INSTALL`; it reaches the image some other way. |

The image needs `vfpk-<arch>` for its architecture in `BBMULTICONFIG`; an
image without flatpak content builds without it. The guest boots under TCG
unless the image is for the build host's architecture, which makes a large
runtime take a minute or so. `FLATPAK_INSTALL_TIMEOUT` (seconds) and
`FLATPAK_INSTALL_MEMORY` (MB, default 2048) tune the guest.

To try it on qemuarm64:

```
BBMULTICONFIG = "vfpk-aarch64"
BUNDLED_FLATPAKS:pn-flatpak-minimal-image = "flathub-freedesktop-platform flutter-remote-manager"
```

### Read-only rootfs: partition and seed

flatpak can only update an installation it can write, so a read-only rootfs
needs `/var/lib/flatpak` on writable storage. With `read-only-rootfs` in
`IMAGE_FEATURES`, `FLATPAK_DEPLOY_MODE` defaults to `partition`:

- The installation is built as an ext4 image, deployed as
  `<image>-<machine>.rootfs.vfpk-data.ext4` (`FLATPAK_DATA_IMAGE`), labeled
  `flatpak` (`FLATPAK_DATA_LABEL`), with `FLATPAK_DATA_EXTRA_SPACE` MB
  (default 1024) of room for updates, or a fixed `FLATPAK_DATA_SIZE` MB. The
  same input gives the same image: its UUID, hash seed and timestamps are
  fixed.
- The rootfs keeps an empty `/var/lib/flatpak` and an fstab entry mounting
  the labeled filesystem there. The entry is ordered after `volatile-binds`,
  which otherwise mounts a RAM copy of `/var/lib` over the partition and
  silently discards updates.
- Place the image with wic, from a `.wks.in`:

  ```
  part /var/lib/flatpak --source rawcopy --fstype=ext4 --no-fstab-update --sourceparams="file=${FLATPAK_DATA_IMAGE}" --label flatpak
  ```

  or with whatever lays out the product's storage. An OS update rewrites the
  rootfs and leaves the partition, and the apps updated on it, alone.

`seed` puts the installation in the rootfs as a tar
(`/usr/share/vfpk/seed.tar`), and `vfpk-seed.service` unpacks it into
`/var/lib/flatpak` on first boot. It never unpacks over an existing
installation, so an OS update with a newer seed keeps what the user updated.
On a read-only rootfs, mount persistent storage at `/var/lib/flatpak` with
`FLATPAK_DATA_FSTAB`, or the seed is unpacked into RAM on every boot.

flatpak lets an unprivileged user update system apps through polkit when
the user has an active local session (a desktop or kiosk session on a seat).
Anything else, such as a background updater, needs a polkit rule.

### Per-user installations

System scope is the default. For a user installation, set:

```bitbake
FLATPAK_INSTALL_SCOPE:pn-agl-ivi-demo-flutter = "user"
FLATPAK_INSTALL_USER:pn-agl-ivi-demo-flutter = "agl-driver"
FLATPAK_DEPLOY_MODE:pn-agl-ivi-demo-flutter = "seed"
```

The build installs apps, runtimes and remotes offline. On first boot,
`vfpk-seed.service` extracts them as that user into `~/.local/share/flatpak`
before the user's session starts; the rest of the boot does not wait. It also
creates an empty system installation, which flatpak needs before unprivileged
commands that cover every installation, such as `flatpak list`, can run.
User scope requires `seed`; the account must exist and its home must be
writable and persistent. Existing installations are preserved; system
installations are not migrated. Custom data-directory locations are unsupported.

Run `flatpak list --user`, `flatpak update --user` and `flatpak run --user <ID>`
as the install account. `:autostart` uses that account by default; an explicit
`FLATPAK_APP_USER` must match it. Custom service units must use the same account,
wait for `vfpk-seed.service` and launch with `--user`.

Both scopes can use first-boot seeding. System scope also supports `rootfs`
and `partition`, which need no extraction. Always launch as the session owner;
root using another user's runtime directory can leave root-owned temporary files.

### Flatpak content built by this build

Three classes turn build output into flatpak refs, committed with
ostree-native into ostree repositories:

- `flatpak-runtime-image` makes an image a runtime: its `/usr` becomes the
  runtime's files and its `/etc` the runtime's `/etc`, with the linker setup
  flatpak expects (`bin/ldconfig`, and app library paths in `ld.so.conf`
  ahead of the image's own). It needs `usrmerge`. A flatpak-bundle recipe
  with `FLATPAK_IMAGE = "<image>"` packages it.
- `flatpak-extension-image` makes an image an extension of such a runtime:
  it holds the files of the image's packages the runtime's image doesn't
  have, so the two are ABI-matched and nothing is shipped twice. A
  flatpak-bundle recipe packages it the same way.
- `flatpak-app` (generic) and `flatpak-flutter-app` (meta-flutter apps) add a
  `${PN}-flatpak` package to an app recipe, holding an app ref made from part
  of what the recipe installs. `${prefix}` maps to `/app`, so installed paths
  keep working, and links into the rest of `${prefix}` resolve in the runtime.
  `FLATPAK_APP_EXTENSIONS` declares extensions the app mounts under `/app`;
  its package depends on theirs.

Both kinds of package install through `flatpak-cross-install` like any other
bundle: `IMAGE_INSTALL += "<app>-flatpak"` or `BUNDLED_FLATPAKS`. The app
package depends on its runtime's package.

Runtime and SDK images select their packages with `FLATPAK_RUNTIME_PACKAGES`;
extension images use `FLATPAK_EXTENSION_PACKAGES`. These feed `PACKAGE_INSTALL`
without using `IMAGE_INSTALL`, so global product additions such as kernel
modules and AGL development tools stay out of sandbox images. Migrate any
runtime or extension recipes and bbappends that set `IMAGE_INSTALL` to the
appropriate variable. Normal package dependencies and requested image features still apply,
including `dev-pkgs` in an SDK. Boot image bootstrap packages such as
`run-postinsts` are not selected: sandbox images have no first boot to run
deferred post-installation scripts.
Bootable images continue to use `IMAGE_INSTALL` as usual.

A runtime built here carries the licenses of its packages: the image lists
them next to the repository, and the packaging recipe's `LICENSE` must name
every one of them, or `do_compile` fails and prints the current list. Each
package is built from its own recipe, so `INCOMPATIBLE_LICENSE` and the
license manifests cover the runtime's contents as they cover the image's.

Refs built here install under `FLATPAK_BUILD_REMOTE`, which must be in
`FLATPAK_REMOTES`. `FLATPAK_GPGID` and `FLATPAK_GPGHOME` sign the commits;
without them the remote needs `FLATPAK_REMOTE_NO_GPG`. Commits are
timestamped with `SOURCE_DATE_EPOCH`.

#### Publishing

Every producer also deploys its refs, like a package feed rather than an
image artifact:

```
tmp/deploy/flatpak/
  refs/<package arch>/<pn>/repo    one repository per producing recipe
  refs/<package arch>/<pn>/licenses  (runtimes) licenses of their packages
  refs/<package arch>/<pn>/*.flatpak  (FLATPAK_DEPLOY_BUNDLES) one bundle per ref
  refs/vfpk-<arch>-generic/<pn>/   the same, from a generic multiconfig
  repo/                            the repository devices update from
  repo-dev/                        the same plus SDKs, for developers
```

`bitbake flatpak-repo-index` merges every deployed ref into `repo/`, keeps
only the current commit of each, signs the summary with `FLATPAK_GPGID`,
and checks it. For a ref that changed it generates a static delta from the
commit published before, so an update downloads one file instead of every
changed object; `FLATPAK_PUBLISH_DELTAS = "previous empty"` adds deltas
from scratch for network installs, at roughly the repository's size again.
A delta goes away with the commit it leads to. Sync `repo/` to the remote's
URL and devices update from it. Like `package-index`, it publishes what has
been deployed; `FLATPAK_PUBLISH_RECIPES` builds named producers first.
`FLATPAK_PUBLISH_EXCLUDE` leaves refs out; the device repository leaves out
SDKs.

`bitbake flatpak-repo-index-dev` does the same into `repo-dev/`, SDKs
included. Publish it apart from the device repository, for developers to
build apps against.

`FLATPAK_DEPLOY_BUNDLES = "1"` on a producer also deploys each of its refs
as a single-file bundle, `<id>-<branch>-<arch>.flatpak`, for
`flatpak install --bundle` where the repository isn't reachable. The
bundle names the remote it updates from, `FLATPAK_DEPLOY_BUNDLE_ORIGIN`
(by default `FLATPAK_REMOTE_URL[<FLATPAK_BUILD_REMOTE>]`), and with
`FLATPAK_GPGID` carries the public key, so flatpak verifies the commit. It
is written with `flatpak-build-bundle-native`, the libostree half of
`flatpak build-bundle`, and is the same commit the repository has. The
Flutter engine extensions turn it on.

A repository holds one commit per ref. Two builds of the same ref for
different CPU tunes or machines (a Cortex-A57 and a Cortex-A76 build of one
aarch64 app) differ, and the index refuses them: publish from one build per
flatpak arch, ideally for a baseline tune, and choose it with
`FLATPAK_PUBLISH_PACKAGE_ARCHS`.

#### Runtimes for every device of an arch

A runtime built for `MACHINE` uses its CPU tune, and a Cortex-A76 build can
fault on a Cortex-A72. To build runtimes once per flatpak arch instead, add
the arch's generic multiconfig and turn it on:

```
BBMULTICONFIG = "vfpk-aarch64 vfpk-aarch64-generic"
FLATPAK_IMAGE_GENERIC = "1"
```

`flatpak-bundle` recipes with `FLATPAK_IMAGE` then build their image in
`vfpk-<arch>-generic` with a baseline tune, and package that:

| Multiconfig | Tune | Also |
| --- | --- | --- |
| `vfpk-aarch64-generic` | `armv8a-crc` (Arm BSA, as `genericarm64`) | Mesa drivers for Broadcom, Vivante, Adreno and Mali Utgard GPUs |
| `vfpk-x86-64-generic` | `core2-64` (as `genericx86-64`) | Mesa's default x86 drivers |
| `vfpk-arm-generic` | `armv7athf-neon` (no VFPv4 or integer divide, for Cortex-A9) | The same Arm drivers as aarch64 |
| `vfpk-riscv64-generic` | `riscv64` (rv64gc, no Zba/Zbb/vector) | Mesa's defaults |

The multiconfig uses the main configuration's distro and `local.conf`, has
its own `TMPDIR`, and deploys refs into the main `tmp/deploy/flatpak/`
under `refs/vfpk-<arch>-generic/`, so `flatpak-repo-index` publishes them.
Build an SDK or other producer there with
`bitbake mc:vfpk-aarch64-generic:flatpak-platform-sdk-image`. Apps are still
built for `MACHINE` and run on the generic runtime as on their own. Delete the main and generic `TMPDIR`s together, or the
generic one keeps believing its refs are deployed.

#### The base runtime and Flutter

The layer's runtime is toolkit-neutral; Flutter's embedder and engine are
extensions:

| Recipe | Content |
| --- | --- |
| `flatpak-platform-runtime-image` | `runtime/org.flatpak_minimal.Platform/<arch>/<release>`: Wayland, Mesa, GLib, GStreamer, fonts, certificates, sqlite |
| `flatpak-platform-runtime` | that runtime, packaged |
| `flatpak-platform-sdk-image` | `runtime/org.flatpak_minimal.Sdk/<arch>/<release>`: the runtime's packages plus their development files, GCC, cmake, ninja, pkg-config |
| `flutter-homescreen-extension-image` | `runtime/org.flatpak_minimal.Flutter.Homescreen/<arch>/<release>`: ivi-homescreen, its plugin library and libc++ (meta-flutter) |
| `flutter-homescreen-extension` | that extension, packaged |
| `flutter-engine-<mode>-extension-image` | `runtime/org.flatpak_minimal.Flutter.Engine.<mode>/<arch>/<engine version>-<release>`: that mode's `libflutter_engine.so` and its ICU data (meta-flutter) |
| `flutter-engine-<mode>-extension` | that extension, packaged |
| `flutter-sdk-extension-image` | `runtime/org.flatpak_minimal.Sdk.Extension.flutter<engine version>/<arch>/<release>`: the engine of `FLUTTER_SDK_EXTENSION_MODES` (default `release`) plus its headers and SDK files, and ivi-homescreen's plugin headers and library (meta-flutter) |

`<mode>` is the engine's runtime mode as meta-flutter names it: `debug`,
`profile`, `release` or `jit_release` (recipes `flutter-engine-jit-release-*`,
since package names cannot have `_`). meta-flutter builds the modes in
`PACKAGECONFIG:pn-flutter-engine`, release by default. `<engine version>` is
the Flutter SDK version and the first 12 digits of the engine commit,
`3.47.7-deb287481e3c`: the commit meta-flutter builds for `FLUTTER_SDK_TAG`
(`conf/include/engine-revision.json`), which an upstream Flutter SDK of that
version names in `bin/internal/engine.version`. A snapshot only runs on the
engine it was compiled for, so the commit is in every engine ref.

`<release>` is the oe-core release (`wrynose`), whose ABI the runtime
carries; `FLATPAK_PLATFORM_BRANCH` overrides it. A Flutter app's metadata
asks for two extensions, which flatpak installs with the app:

- the embedder, ivi-homescreen, at `/app/homescreen`. It loads
  `libflutter_engine.so` from the app's bundle through the embedder API and
  has no runtime mode or engine version of its own, so it is branched by the
  runtime only: one install serves every Flutter app, and a fix to it is an
  update in place.
- the engine of the app's mode (`FLATPAK_FLUTTER_RUNTIME_MODE`) and engine
  version, at `/app/flutter`, where the bundle's engine links point. Every
  mode and engine version is its own ref, so they install side by side.
  Each engine is also deployed as a bundle named for its mode and engine
  version,
  `org.flatpak_minimal.Flutter.Engine.release-3.47.7-deb287481e3c-wrynose-aarch64.flatpak`.

Apps share the runtime and the embedder, each mode and engine in use adds
one extension, and a Mesa fix is one runtime update for all of them.

The SDK names the runtime with `runtime=`, so native code built with
flatpak-builder in the SDK runs in the runtime. The Flutter SDK extension
carries the engine version in its ID, since an SDK extension's branch is the
SDK's, and mounts at `/usr/lib/sdk/flutter<engine version>`, with an `enable.sh`
that sets `PATH`, `CPATH`, `LIBRARY_PATH`, `PKG_CONFIG_PATH` and, for each
mode it carries, `FLUTTER_ENGINE_<MODE>` (`FLUTTER_ENGINE_RELEASE`). There is no Dart AOT compiler: meta-flutter builds
`gen_snapshot` for the build machine only, so an app's Dart code is still
compiled on the host.

To build with it on a workstation, publish `repo-dev`, add it as a remote
and point flatpak-builder at the SDK. Another arch builds through
qemu-user (binfmt):

```
flatpak --user remote-add --no-gpg-verify vfpk-dev file:///path/to/tmp/deploy/flatpak/repo-dev
flatpak --user install --arch=aarch64 vfpk-dev org.flatpak_minimal.Sdk//wrynose \
    org.flatpak_minimal.Platform//wrynose org.flatpak_minimal.Sdk.Extension.flutter3_47_7_deb287481e3c//wrynose \
    org.flatpak_minimal.Flutter.Engine.release//3.47.7-deb287481e3c-wrynose
flatpak-builder --arch=aarch64 --repo=repo build-dir org.example.App.yml
```

with a manifest such as:

```yaml
app-id: org.example.App
runtime: org.flatpak_minimal.Platform
runtime-version: 'wrynose'
sdk: org.flatpak_minimal.Sdk
sdk-extensions:
  - org.flatpak_minimal.Sdk.Extension.flutter3_47_7_deb287481e3c
add-extensions:
  org.flatpak_minimal.Flutter.Engine.release:
    directory: flutter
    version: '3.47.7-deb287481e3c-wrynose'
build-options:
  env:
    CPATH: /usr/lib/sdk/flutter3_47_7_deb287481e3c/include
    FLUTTER_ENGINE_RELEASE: /usr/lib/sdk/flutter3_47_7_deb287481e3c/share/flutter/3.47.7/release
command: example
modules:
  - name: example
    buildsystem: cmake-ninja
    post-install:
      - install -d /app/flutter
    sources:
      - type: dir
        path: src
```

`flutter_embedder.h` is then on the include path, and code links the engine
with `-L$FLUTTER_ENGINE_RELEASE/lib -lflutter_engine` and an rpath of
`/app/flutter/share/flutter/3.47.7/release/lib`. `add-extensions` gives the
app the same engine extension point `flatpak-flutter-app` writes; the
`post-install` line creates its mount point, which `/app` needs since it is
read-only at run time. An app that runs ivi-homescreen adds
`org.flatpak_minimal.Flutter.Homescreen` (`directory: homescreen`,
`version: 'wrynose'`, `add-ld-path: lib`) the same way.

`FLATPAK_RUNTIME_GL = "extension"` moves the GL stack out of a runtime into
its own extension, `<runtime>.GL.default`, built from the same image. The
runtime keeps an extension point at `/usr/lib/GL`, as Freedesktop's does;
flatpak mounts the extension for each active GL driver and puts its
libraries on the linker path. Another build can then ship a different GPU's
stack as `<runtime>.GL.<name>`, picked on the device with
`FLATPAK_GL_DRIVERS=<name>`. The libraries move whole (no libglvnd), so a
vendor stack with its own `libEGL` fits too. The default, `runtime`, keeps
Mesa in the runtime.

A Flutter app opts in with:

```
inherit flutter-app-native flatpak-flutter-app
FLATPAK_APP_ID = "org.example.App"
```

and runs as `/app/homescreen/bin/homescreen -b /app/share/flutter/<app>/<version>/release`
on `org.flatpak_minimal.Platform`, with the homescreen extension and the
engine extension of its mode and engine version.
`flatpak-minimal-appstream-dart-flathub-catalog` is packaged this way.

### Testing

`conf/include/vfpk-testimage.inc` builds `flatpak-minimal-image` with a
small test runtime and app (`recipes-test/vfpk-test`, buildable for every
supported architecture) installed at build time, and boots it under
testimage:

```
BBMULTICONFIG = "vfpk-aarch64"
require conf/include/vfpk-testimage.inc
```

```
bitbake flatpak-minimal-image -c testimage
```

The `flatpak` test suite (`lib/oeqa/runtime/cases/flatpak.py`) checks that
every ref in `/usr/share/vfpk/installed.refs` is deployed at its commit under
its origin, that the origins are configured remotes, that `flatpak repair`
is clean and that the test app runs in its sandbox. CI runs it on all four
machines. The include lets root log in without a password; it is for tests
only.

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
