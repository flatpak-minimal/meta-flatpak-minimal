// SPDX-License-Identifier: LGPL-2.0-or-later
fn main() {
    // libostree and libflatpak link this by its soname.
    println!("cargo:rustc-cdylib-link-arg=-Wl,-soname,libopenpgp_verify_sequoia.so.0");
}
