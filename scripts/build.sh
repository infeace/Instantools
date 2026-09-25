#!/usr/bin/env bash
# Builds build/Instantools.app, with each tool as a helper inside it, and signs it with a stable local
# identity so macOS keeps granted permissions across rebuilds.
# Usage: scripts/build.sh [--debug] [--install] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id="com.infeace.Instantools"
# Product name, file name in Contents/Helpers, signing identifier.
tools=(
    "AppSwitcher InstantoolsAppSwitcher $bundle_id.AppSwitcher"
    "LayoutSwitcher InstantoolsLayoutSwitcher $bundle_id.LayoutSwitcher"
)
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

# The host and its tools running from under a path. By full path, since macOS cuts process names to 16
# characters, too short for the tools' names.
pids_under() {
    local prefix="$1" pid comm
    ps -axo pid=,comm= | while read -r pid comm; do
        [[ "$comm" == "$prefix"* ]] || continue
        case "${comm##*/}" in
            Instantools | InstantoolsAppSwitcher | InstantoolsLayoutSwitcher) echo "$pid" ;;
        esac
    done
}

# Replacing the binary of a running event tap owner can leave input in a bad state, so quit first.
stop_running() {
    local prefix="$1" pids
    pids="$(pids_under "$prefix")"
    [[ -z "$pids" ]] && return 0
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
    for _ in {1..50}; do
        [[ -z "$(pids_under "$prefix")" ]] && return 0
        sleep 0.1
    done
    echo "error: Instantools under $prefix did not quit, not replacing it" >&2
    exit 1
}

# Instantools replaces InstantTab and InstantLang. They stay installed with their settings, so either can
# be started again to go back.
retire_old_apps() {
    local name label plist pids
    for name in InstantTab InstantLang; do
        label="com.infeace.$name"
        plist="$HOME/Library/LaunchAgents/$label.plist"
        if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
            echo "Unloading the $name login agent"
            launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        fi
        pids="$(pgrep -x "$name" || true)"
        if [[ -n "$pids" ]]; then
            echo "Quitting $name"
            # shellcheck disable=SC2086
            kill -TERM $pids 2>/dev/null || true
            for _ in {1..50}; do
                pgrep -x "$name" >/dev/null || break
                sleep 0.1
            done
        fi
        if [[ -f "$plist" ]]; then
            echo "Removing $plist. To go back to $name, quit Instantools, open $name and turn Start at login back on."
            rm "$plist"
            # Instantools' first launch turns on its own Start at login when an old app had it.
            defaults write "$bundle_id" removedOldLoginAgents -array-add "$name"
        fi
    done
}

swift build -c "$config"
bin_dir="$(swift build -c "$config" --show-bin-path)"

app=build/Instantools.app
stop_running "$PWD/$app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin_dir/Instantools" "$app/Contents/MacOS/Instantools"
for tool in "${tools[@]}"; do
    read -r product helper _ <<<"$tool"
    cp "$bin_dir/$product" "$app/Contents/Helpers/$helper"
done
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"

# The second is the identity InstantTab used, so a Mac set up for it needs no new one.
identities="$(security find-identity -v -p codesigning)"
identity=""
for candidate in "Instantools Local Signing" "InstantTab Local Signing"; do
    if grep -q "\"$candidate\"" <<<"$identities"; then
        identity="$candidate"
        break
    fi
done
if [[ -z "$identity" ]]; then
    echo "warning: signing identity 'Instantools Local Signing' not found, signing ad hoc." >&2
    echo "warning: permissions will reset on every build. Run scripts/create-signing-cert.sh once." >&2
    identity="-"
fi
# Helpers first: signing the app seals them in.
for tool in "${tools[@]}"; do
    read -r _ helper identifier <<<"$tool"
    codesign --force --sign "$identity" --identifier "$identifier" "$app/Contents/Helpers/$helper"
done
codesign --force --sign "$identity" --identifier "$bundle_id" "$app"
codesign --verify --strict --deep "$app"

# Start at login writes this agent (see LoginItem.swift).
agent="gui/$(id -u)/$bundle_id"
if [[ $install -eq 1 ]]; then
    stop_running "$HOME/Applications/Instantools.app"
    retire_old_apps
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Instantools.app"
    ditto "$app" "$HOME/Applications/Instantools.app"
    app="$HOME/Applications/Instantools.app"
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
