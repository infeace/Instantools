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

# Replacing the binary of a running event tap owner can leave input in a bad state, so quit first.
stop_running() {
    local path_prefix="$1" pid
    for pid in $(pgrep -x InstantTab); do
        [[ "$(ps -o comm= -p "$pid" 2>/dev/null)" == "$path_prefix"* ]] && { kill -TERM "$pid" 2>/dev/null || true; }
    done
    for _ in {1..50}; do
        local alive=0
        for pid in $(pgrep -x InstantTab); do
            [[ "$(ps -o comm= -p "$pid" 2>/dev/null)" == "$path_prefix"* ]] && alive=1
        done
        [[ $alive -eq 0 ]] && return 0
        sleep 0.1
    done
    echo "error: InstantTab under $path_prefix did not quit, not replacing it" >&2
    exit 1
}

swift build -c "$config"
bin_dir="$(swift build -c "$config" --show-bin-path)"

app=build/InstantTab.app
stop_running "$PWD/$app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/InstantTab" "$app/Contents/MacOS/InstantTab"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"

identities="$(security find-identity -v -p codesigning)"
if grep -q "\"$identity\"" <<<"$identities"; then
    codesign --force --sign "$identity" --identifier "$bundle_id" "$app"
else
    echo "warning: signing identity '$identity' not found, signing ad hoc." >&2
    echo "warning: permissions will reset on every build. Run scripts/create-signing-cert.sh once." >&2
    codesign --force --sign - --identifier "$bundle_id" "$app"
fi
codesign --verify --strict "$app"

# Start at login writes this agent (see LoginItem.swift).
agent="gui/$(id -u)/com.infeace.InstantTab"
if [[ $install -eq 1 ]]; then
    stop_running "$HOME/Applications/InstantTab.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/InstantTab.app"
    ditto "$app" "$HOME/Applications/InstantTab.app"
    app="$HOME/Applications/InstantTab.app"
fi

echo "built $app"
if [[ $run -eq 1 ]]; then
    # When Start at Login is on, relaunch under the agent so crash relaunch keeps working.
    if [[ $install -eq 1 ]] && launchctl print "$agent" >/dev/null 2>&1; then
        launchctl kickstart -k "$agent"
    else
        # Only one copy runs at a time, so stop any other before opening this one.
        stop_running "/"
        open "$app"
    fi
fi
