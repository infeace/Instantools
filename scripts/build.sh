#!/usr/bin/env bash
# Builds build/InstantTab.app and signs it with the stable local identity so macOS
# keeps granted permissions across rebuilds.
# Usage: scripts/build.sh [--debug] [--install] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

identity="InstantTab Local Signing"
bundle_id="com.infeace.InstantTab"
config=release
install=0
run=0
for arg in "$@"; do
    case "$arg" in
        --debug) config=debug ;;
        --install) install=1 ;;
        --run) run=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

swift build -c "$config"
bin_dir="$(swift build -c "$config" --show-bin-path)"

app=build/InstantTab.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/InstantTab" "$app/Contents/MacOS/InstantTab"
cp Resources/Info.plist "$app/Contents/Info.plist"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"

if security find-identity -v -p codesigning | grep -q "\"$identity\""; then
    codesign --force --sign "$identity" --identifier "$bundle_id" "$app"
else
    echo "warning: signing identity '$identity' not found, signing ad hoc." >&2
    echo "warning: permissions will reset on every build. Run scripts/create-signing-cert.sh once." >&2
    codesign --force --sign - --identifier "$bundle_id" "$app"
fi
codesign --verify --strict "$app"

if [[ $install -eq 1 ]]; then
    # Replacing the binary of a running event tap owner can leave input in a bad state, so quit first.
    if pgrep -x InstantTab >/dev/null; then
        pkill -TERM -x InstantTab
        for _ in {1..50}; do pgrep -x InstantTab >/dev/null || break; sleep 0.1; done
        if pgrep -x InstantTab >/dev/null; then
            echo "error: InstantTab did not quit, not replacing it" >&2
            exit 1
        fi
    fi
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/InstantTab.app"
    ditto "$app" "$HOME/Applications/InstantTab.app"
    app="$HOME/Applications/InstantTab.app"
fi

echo "built $app"
if [[ $run -eq 1 ]]; then
    open "$app"
fi
