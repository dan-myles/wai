#!/bin/sh
# Installs wai from GitHub Releases (macOS, Linux): picks the binary for this OS and CPU, checks its
# SHA-256, puts it in ~/.local/bin, records the install so `wai update` can replace it later, then
# runs `wai install` (links the addon into WoW: Forever and starts the bridge at login).
#
#   curl -fsSL https://raw.githubusercontent.com/dan-myles/wai/main/install.sh | sh
#   sh install.sh --version v0.1.0 --wow "/Applications/World of Warcraft/_forever_"
#
# The repo is private: with the GitHub CLI signed in (`gh auth login`) downloads just work.
set -eu

REPO="${WAI_REPO:-dan-myles/wai}"
VERSION=""
WOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --wow) WOW="$2"; shift 2 ;;
    *) echo "wai: unknown option $1" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;33mwai\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mwai\033[0m %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "unsupported OS $(uname -s); on Windows use install.ps1" ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  x86_64 | amd64) arch=x64 ;;
  *) fail "unsupported CPU $(uname -m)" ;;
esac
[ "$os" = linux ] && arch=x64
asset="wai-$os-$arch"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading $asset ${VERSION:-(latest)}…"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if [ -n "$VERSION" ]; then
    gh release download "$VERSION" --repo "$REPO" --pattern "$asset" --pattern SHA256SUMS --dir "$tmp"
  else
    gh release download --repo "$REPO" --pattern "$asset" --pattern SHA256SUMS --dir "$tmp"
  fi
else
  if [ -n "$VERSION" ]; then base="https://github.com/$REPO/releases/download/$VERSION"; else base="https://github.com/$REPO/releases/latest/download"; fi
  curl -fsSL -o "$tmp/$asset" "$base/$asset" || fail "download failed. The repo is private: install the GitHub CLI and run 'gh auth login' first."
  curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" || fail "couldn't download SHA256SUMS"
fi

expected="$(grep " $asset\$" "$tmp/SHA256SUMS" | cut -d' ' -f1)"
if command -v shasum >/dev/null 2>&1; then actual="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"; else actual="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"; fi
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "checksum mismatch for $asset; nothing was installed"

bindir="$HOME/.local/bin"
bin="$bindir/wai"
mkdir -p "$bindir" "$HOME/.wai"
chmod +x "$tmp/$asset"
# macOS refuses unsigned arm64 binaries; an ad-hoc signature is enough.
[ "$os" = darwin ] && codesign --force --sign - "$tmp/$asset" >/dev/null 2>&1 || true
mv -f "$tmp/$asset" "$bin"

version="$("$bin" version | cut -d' ' -f2)"
printf '{\n  "managed": true,\n  "version": "%s",\n  "path": "%s",\n  "installedAt": "%s"\n}\n' \
  "$version" "$bin" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HOME/.wai/install.json"
say "Installed wai $version to $bin"

case ":$PATH:" in
  *":$bindir:"*) ;;
  *)
    profile="$HOME/.profile"
    case "${SHELL:-}" in */zsh) profile="$HOME/.zprofile" ;; */bash) profile="$HOME/.bashrc" ;; esac
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
    say "Added ~/.local/bin to PATH in $profile (open a new terminal to use 'wai')."
    ;;
esac

if [ -n "$WOW" ]; then "$bin" install --wow "$WOW"; else "$bin" install; fi
