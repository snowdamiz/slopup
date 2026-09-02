#!/bin/zsh

set -euo pipefail
umask 077

repository="${SLOPUP_REPOSITORY:-__GITHUB_REPOSITORY__}"
install_dir="${SLOPUP_INSTALL_DIR:-$HOME/Applications}"

fail() {
    echo "slopup: $1" >&2
    exit 1
}

[[ "$repository" != "__GITHUB_REPOSITORY__" ]] || fail "use the installer from a GitHub Release"
[[ "$repository" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] || fail "invalid GitHub repository: $repository"
[[ "$install_dir" == /* && "$install_dir" != "/" && "$install_dir" != "$HOME" ]] || fail "install directory must be a safe absolute path"

temporary_dir="$(mktemp -d)"
target="$install_dir/Slopup.app"
staging="$install_dir/.Slopup.installing.$$"
backup="$install_dir/.Slopup.previous.$$"

cleanup() {
    if [[ -d "$backup" && ! -e "$target" ]]; then
        mv "$backup" "$target"
    fi
    rm -rf "$temporary_dir" "$staging" "$backup"
}
trap cleanup EXIT

base_url="https://github.com/$repository/releases/latest/download"
curl --fail --location --silent --show-error "$base_url/Slopup.zip" --output "$temporary_dir/Slopup.zip"
curl --fail --location --silent --show-error "$base_url/SHA256SUMS" --output "$temporary_dir/SHA256SUMS"

expected="$(awk '$2 == "Slopup.zip" { print $1 }' "$temporary_dir/SHA256SUMS")"
actual="$(shasum -a 256 "$temporary_dir/Slopup.zip" | awk '{ print $1 }')"
[[ -n "$expected" && "$actual" == "$expected" ]] || fail "release checksum verification failed"

ditto -x -k "$temporary_dir/Slopup.zip" "$temporary_dir/unpacked"
source_app="$temporary_dir/unpacked/Slopup.app"
[[ -x "$source_app/Contents/MacOS/Slopup" ]] || fail "release does not contain Slopup.app"
codesign --verify --deep --strict "$source_app" || fail "release signature is invalid"

mkdir -p "$install_dir"
[[ ! -e "$staging" && ! -e "$backup" ]] || fail "another installation appears to be running"
ditto "$source_app" "$staging"

osascript -e 'tell application id "app.slopup.Slopup" to quit' >/dev/null 2>&1 || true
if [[ -e "$target" ]]; then
    [[ -d "$target" && ! -L "$target" ]] || fail "$target is not an app directory"
    mv "$target" "$backup"
fi
mv "$staging" "$target"

version="$(defaults read "$target/Contents/Info" CFBundleShortVersionString)"
echo "Slopup $version installed in $target"
if [[ "${SLOPUP_NO_OPEN:-0}" != "1" ]]; then
    open "$target"
fi
