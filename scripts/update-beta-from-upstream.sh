#!/usr/bin/env bash
# Sync beta/PKGBUILD + beta/.SRCINFO with the newest Synara beta GitHub release.
#
# Only prereleases that actually ship a Linux AppImage are considered, which
# skips the mac-only "vX.Y.Z-remote.N" prereleases automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-Emanuele-web04/synara}"
PKGDIR="$ROOT/beta"
cd "$PKGDIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }
need gh
need jq
need python3

releases_json="$(gh api "repos/${UPSTREAM_REPO}/releases?per_page=30")"

# Releases come back newest first; take the newest prerelease with a Linux asset.
pick="$(
  jq -c '
    [ .[]
      | select(.prerelease == true)
      | { tag: .tag_name,
          asset: ([ .assets[] | select(.name | test("^Synara-Beta-.*-x86_64\\.AppImage$")) ] | first) }
    ]
    | map(select(.asset != null))
    | .[0] // empty
  ' <<<"$releases_json"
)"

if [[ -z "$pick" ]]; then
  echo "No beta prerelease with a Linux AppImage found; refusing to update."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "updated=false" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi

tag="$(jq -r '.tag' <<<"$pick")"
asset_name="$(jq -r '.asset.name' <<<"$pick")"

if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-beta\.([0-9]+)$ ]]; then
  echo "Unsupported beta tag format: $tag (expected vX.Y.Z-beta.N)" >&2
  exit 1
fi

upstream_ver="${BASH_REMATCH[1]}-beta.${BASH_REMATCH[2]}"
version="${BASH_REMATCH[1]}_beta.${BASH_REMATCH[2]}"
current_ver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"

if [[ "$current_ver" == "$version" ]]; then
  echo "Already at $version; nothing to do."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "updated=false" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi

digest="$(jq -r '.asset.digest // empty' <<<"$pick")"
if [[ "$digest" == sha256:* ]]; then
  appimage_sha="${digest#sha256:}"
else
  echo "GitHub asset digest missing; downloading to compute sha256..." >&2
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  gh release download "$tag" --repo "$UPSTREAM_REPO" --pattern "$asset_name" --output "$tmp"
  appimage_sha="$(sha256sum "$tmp" | awk '{print $1}')"
fi

license_url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/v${upstream_ver}/LICENSE"
license_tmp="$(mktemp)"
curl -fsSL "$license_url" -o "$license_tmp"
license_sha="$(sha256sum "$license_tmp" | awk '{print $1}')"
cp "$license_tmp" LICENSE
rm -f "$license_tmp"

desktop_sha="$(sha256sum synara-beta.desktop | awk '{print $1}')"
icon_sha="$(sha256sum synara-beta.svg | awk '{print $1}')"

echo "Updating $current_ver -> $version (upstream $upstream_ver, $asset_name)"

python3 - "$version" "$appimage_sha" "$desktop_sha" "$icon_sha" "$license_sha" <<'PY'
import pathlib, sys

version, app_sha, desktop_sha, icon_sha, license_sha = sys.argv[1:]
path = pathlib.Path("PKGBUILD")
lines = path.read_text().splitlines(keepends=True)
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

echo "Updated beta/PKGBUILD to $version"
