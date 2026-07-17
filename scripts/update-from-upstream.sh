#!/usr/bin/env bash
# Sync PKGBUILD + .SRCINFO with the latest stable Synara GitHub release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-Emanuele-web04/synara}"
cd "$ROOT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }
need gh
need jq
need python3

release_json="$(gh api "repos/${UPSTREAM_REPO}/releases/latest")"
tag="$(jq -r '.tag_name' <<<"$release_json")"
prerelease="$(jq -r '.prerelease' <<<"$release_json")"

if [[ "$prerelease" == "true" ]]; then
  echo "Latest release $tag is a prerelease; refusing to update."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "updated=false" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi

if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "Unsupported tag format: $tag (expected vX.Y.Z)" >&2
  exit 1
fi

version="${BASH_REMATCH[1]}"
asset_name="Synara-${version}-x86_64.AppImage"
current_ver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"

if [[ "$current_ver" == "$version" ]]; then
  echo "Already at $version; nothing to do."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "updated=false" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi

asset_json="$(
  jq -c --arg name "$asset_name" '.assets[] | select(.name == $name)' <<<"$release_json"
)"
if [[ -z "$asset_json" || "$asset_json" == "null" ]]; then
  echo "Release $tag is missing $asset_name" >&2
  exit 1
fi

digest="$(jq -r '.digest // empty' <<<"$asset_json")"
if [[ "$digest" == sha256:* ]]; then
  appimage_sha="${digest#sha256:}"
else
  echo "GitHub asset digest missing; downloading to compute sha256..." >&2
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  gh release download "$tag" --repo "$UPSTREAM_REPO" --pattern "$asset_name" --output "$tmp"
  appimage_sha="$(sha256sum "$tmp" | awk '{print $1}')"
fi

license_url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/v${version}/LICENSE"
license_tmp="$(mktemp)"
curl -fsSL "$license_url" -o "$license_tmp"
license_sha="$(sha256sum "$license_tmp" | awk '{print $1}')"
cp "$license_tmp" LICENSE
rm -f "$license_tmp"

desktop_sha="$(sha256sum synara.desktop | awk '{print $1}')"
icon_sha="$(sha256sum synara.png | awk '{print $1}')"

echo "Updating $current_ver -> $version"

python3 - "$version" "$appimage_sha" "$desktop_sha" "$icon_sha" "$license_sha" <<'PY'
import pathlib, sys

version, app_sha, desktop_sha, icon_sha, license_sha = sys.argv[1:]
path = pathlib.Path("PKGBUILD")
text = path.read_text()
lines = text.splitlines(keepends=True)
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith("pkgver="):
        out.append(f"pkgver={version}\n")
    elif line.startswith("pkgrel="):
        out.append("pkgrel=1\n")
    elif line.startswith("sha256sums=("):
        out.append(line)
        i += 1
        # Skip existing sum lines until closing paren
        while i < len(lines) and not lines[i].strip().startswith(")"):
            i += 1
        out.append(f"  '{app_sha}'\n")
        out.append(f"  '{desktop_sha}'\n")
        out.append(f"  '{icon_sha}'\n")
        out.append(f"  '{license_sha}'\n")
        if i < len(lines):
            out.append(lines[i])  # closing )
    else:
        out.append(line)
    i += 1
path.write_text("".join(out))
PY

if command -v makepkg >/dev/null 2>&1; then
  makepkg --printsrcinfo >.SRCINFO
else
  echo "makepkg unavailable; .SRCINFO must be regenerated elsewhere." >&2
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "updated=true"
    echo "version=$version"
    echo "tag=$tag"
    echo "previous=$current_ver"
  } >>"$GITHUB_OUTPUT"
fi

echo "Updated PKGBUILD to $version"
