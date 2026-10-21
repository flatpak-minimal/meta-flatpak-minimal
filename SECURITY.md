# Security policy

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability reporting on
<https://github.com/flatpak-minimal/meta-flatpak-minimal/security/advisories/new>,
or email the maintainer, Joel Winarske <joel.winarske@linux.com>.

Include the affected recipe or class, the layer revision, and how to
reproduce the problem. Expect an acknowledgement within a week.

## Scope

This layer builds images; most vulnerabilities are in the software it builds
and belong upstream (flatpak, ostree, bubblewrap, the Flutter engine, ...) or
in openembedded-core and meta-openembedded. Report those to the respective
projects. Issues in this layer's own recipes, classes and scripts, such as the
build-time flatpak install (vfpk) or the remotes and signing keys it ships,
are in scope here.

## Supported branches

Fixes land on `master`. Release branches receive fixes while they track a
supported Yocto release.
