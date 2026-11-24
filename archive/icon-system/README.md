# Archived Icon System

All custom/packaged icon assets (`synara.png`, `synara-code.svg`, `synara-beta.svg`) are kept here for historical reference only.

This directory is excluded from AUR syncs (`.github/workflows/update-aur.yml`), and `scripts/retire-icon-system.sh` ensures `PKGBUILD`, `beta/PKGBUILD`, `synara.desktop`, and `beta/synara-beta.desktop` do not ship or point to packaged icons—letting Synara manage its own runtime icons.
