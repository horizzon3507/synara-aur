#!/usr/bin/env bash
# Idempotently strip packaged icon wiring from both channels (stable & beta)
# so Synara manages its own runtime icon without PKGBUILD/.desktop overrides.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])

targets = [
    (root / "PKGBUILD", root / "synara.desktop", "synara.desktop"),
    (root / "beta" / "PKGBUILD", root / "beta" / "synara-beta.desktop", "synara-beta.desktop"),
]

for pkgbuild_path, desktop_path, _desktop_name in targets:
    if desktop_path.exists():
        desktop_lines = [
            line for line in desktop_path.read_text().splitlines(keepends=True)
            if not line.startswith("Icon=")
        ]
        desktop_path.write_text("".join(desktop_lines))

    desktop_sha = hashlib.sha256(desktop_path.read_bytes()).hexdigest()

    text = pkgbuild_path.read_text()

    # Remove hicolor-icon-theme from depends.
    text = re.sub(r"\s*'hicolor-icon-theme'", "", text)

    # Remove the hicolor icon install block and its comment.
    text = re.sub(
        r"\n\s*# The AppImage ships its own hicolor icon;[^\n]*\n"
        r"(?:\s*#[^\n]*\n)*"
        r"\s*install -Dm644 squashfs-root/usr/share/icons/hicolor/[^\n]*\\\n"
        r"\s*\"\$\{pkgdir\}/usr/share/icons/hicolor/[^\n]*\n",
        "\n",
        text,
    )

    # Update the 2nd sha256sums entry (the .desktop file).
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        if line.startswith("sha256sums=("):
            idx = 0
            i += 1
            while i < len(lines) and not lines[i].strip().startswith(")"):
                if idx == 1:
                    out.append(f"  '{desktop_sha}'\n")
                else:
                    out.append(lines[i])
                idx += 1
                i += 1
            if i < len(lines):
                out.append(lines[i])
        i += 1

    pkgbuild_path.write_text("".join(out))
PY

if command -v makepkg >/dev/null 2>&1; then
  (cd "$ROOT" && makepkg --printsrcinfo >.SRCINFO)
  (cd "$ROOT/beta" && makepkg --printsrcinfo >.SRCINFO)
else
  echo "makepkg unavailable; .SRCINFO files were not regenerated." >&2
fi

echo "Packaged icon system retired; .desktop entries no longer point to an icon."
