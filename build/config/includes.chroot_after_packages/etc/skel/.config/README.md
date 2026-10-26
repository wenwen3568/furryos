# Placeholder for KDE per-user configuration injected into /etc/skel.

## What belongs here (and who owns it)

Per docs/CONTRACTS.md the single owner of
`/etc/skel/.config/kdeglobals` is **desktop-visual** (colors + wallpaper),
merging in **motion-effects**' click-effect settings. build-verify must not
write this file, so this directory ships empty in the live-build tree and is
populated at integration time by the FurryOS asset-integration hook.

The integration hook (config/hooks/normal/6110-integrate-desktop-assets.chroot)
copies the owners' files here from the staged assets directory, e.g.:

    /etc/skel/.config/kdeglobals           <- assets/desktop/skel/.config/kdeglobals
                                              (already merged with assets/effects'
                                              click-effect keys by desktop-visual)
    /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
    /etc/skel/.config/kwinrc               <- assets/effects/ (if present)

## Why an empty directory is kept in git

live-build's `Find_files` uses `ls | grep -qs .`, which ignores dotfiles at
the top level but does see them once a path is given. Keeping the directory
present documents the contract and prevents `lb config` from pruning it.
