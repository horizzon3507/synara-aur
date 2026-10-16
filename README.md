# synara (AUR)

Unofficial Arch User Repository package for [Synara](https://github.com/Emanuele-web04/synara).

Installs the upstream Linux AppImage into `/opt/synara`, with `/usr/bin/synara`, a `.desktop` entry, and an icon.

## Install

```bash
yay -S synara
# or
paru -S synara
```

## Notes

- Package name is `synara` (binary/AppImage packaging).
- Tracks stable upstream releases only.
- Community packaging — not an official Synara project package.

## Beta channel

A second package, `synara-beta`, tracks upstream prereleases (the `-beta.N`
builds). It is co-installable with the stable one:

```bash
yay -S synara-beta
```

It installs under `/opt/synara-beta` with the `/usr/bin/synara-beta` launcher, so
both channels can be present at the same time. Packaging files live in `beta/`.

