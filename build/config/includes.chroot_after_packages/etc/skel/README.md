# FurryOS default user configuration (/etc/skel)

Everything under this directory is copied into the live system's `/etc/skel`
by live-build's `lb chroot_includes_after_packages` stage, so every account
created after installation (including the live session user created by
live-config) starts with the FurryOS look and feel already configured.

## Ownership (per docs/CONTRACTS.md conflict table)

| Path in this tree | Owner |
|---|---|
| `etc/skel/.config/kdeglobals` | desktop-visual (colors + wallpaper) + motion-effects (click effect), merged by desktop-visual |
| `etc/skel/.config/plasma-*` | desktop-visual |
| `etc/skel/.config/kwinrc`, `ksmserverrc`, `kdeglobals` click section | motion-effects |
| `etc/skel/.face`, `etc/skel/.face.icon` | build-verify (brand avatar) |

build-verify only owns the brand avatar and the directory scaffolding.
The `kdeglobals` file itself is written by desktop-visual / motion-effects and
is **not** created here so that the single-owner rule is never violated.

## Injection order

`includes.chroot_after_packages` is applied after all package lists are
installed, so the KDE packages that own `/etc/skel`'s defaults (e.g.
`plasma-workspace`'s `/etc/skel/.config`) are already present. Files placed
here overwrite the package-provided defaults.

live-build copies with `rsync -Klrv --chown=0:0`, so ownership is forced to
root:root and symlinks are preserved as symlinks.
