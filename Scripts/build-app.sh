#!/bin/zsh

set -euo pipefail

configuration="${1:-debug}"
architecture="${2:-native}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "usage: $0 [debug|release] [native|universal]" >&2
    exit 2
fi
if [[ "$architecture" != "native" && "$architecture" != "universal" ]]; then
    echo "usage: $0 [debug|release] [native|universal]" >&2
    exit 2
fi

project_dir="${0:A:h:h}"
app_dir="$project_dir/build/Slopup.app"

cd "$project_dir"
if [[ "$architecture" == "universal" ]]; then
    arm_scratch="$project_dir/.build/universal-arm64"
    intel_scratch="$project_dir/.build/universal-x86_64"
    swift build --configuration "$configuration" --triple arm64-apple-macosx14.0 --scratch-path "$arm_scratch" --product Slopup
    swift build --configuration "$configuration" --triple x86_64-apple-macosx14.0 --scratch-path "$intel_scratch" --product Slopup
    arm_binary_dir="$(swift build --configuration "$configuration" --triple arm64-apple-macosx14.0 --scratch-path "$arm_scratch" --show-bin-path)"
    intel_binary_dir="$(swift build --configuration "$configuration" --triple x86_64-apple-macosx14.0 --scratch-path "$intel_scratch" --show-bin-path)"
    resource_dir="$arm_binary_dir/Slopup_Slopup.bundle"
else
    swift build --configuration "$configuration" --product Slopup
    binary_dir="$(swift build --configuration "$configuration" --show-bin-path)"
    resource_dir="$binary_dir/Slopup_Slopup.bundle"
fi

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources/ProviderLogos"
if [[ "$architecture" == "universal" ]]; then
    lipo -create "$arm_binary_dir/Slopup" "$intel_binary_dir/Slopup" -output "$app_dir/Contents/MacOS/Slopup"
else
    cp "$binary_dir/Slopup" "$app_dir/Contents/MacOS/Slopup"
fi
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$resource_dir/MenuBarIcon.svg" "$app_dir/Contents/Resources/MenuBarIcon.svg"
for logo in "$resource_dir/"*.svg; do
    [[ "${logo:t}" == "MenuBarIcon.svg" ]] && continue
    cp "$logo" "$app_dir/Contents/Resources/ProviderLogos/"
done
codesign --force --sign - "$app_dir" >/dev/null

echo "$app_dir"
