#!/usr/bin/env bash
#
# Build a Release copy, make /Applications the single installed copy, and
# clear every other registration.
#
# Why this exists: every build location that is launched registers its own
# Quick Look extension, and the records outlive the directories. A worktree
# built under /private/tmp leaves a ghost in System Settings long after the
# directory is gone, and with several of them there is no way to tell which
# copy Finder actually invoked. One installed copy at a known path removes the
# ambiguity.
#
# Usage:
#   scripts/install-to-applications.sh [--reset-config] [--keep-derived-data]
#
#   --reset-config       delete the App Group config.json so the next preview
#                        falls back to the bundled default
#   --keep-derived-data  leave the built .app in DerivedData (it will register
#                        itself again if it is ever launched)

set -euo pipefail

RESET_CONFIG=0
KEEP_DERIVED_DATA=0
for arg in "$@"; do
    case "$arg" in
        --reset-config) RESET_CONFIG=1 ;;
        --keep-derived-data) KEEP_DERIVED_DATA=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO/AllYouNeedQuickLook.xcodeproj"
APP_NAME="AllYouNeedQuickLook.app"
INSTALLED="/Applications/$APP_NAME"
GROUP_CONTAINER="$HOME/Library/Group Containers/group.com.yohanpark.AllYouNeedQuickLook"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Quitting any running copy"
osascript -e 'tell application "AllYouNeedQuickLook" to quit' 2>/dev/null || true
pkill -f "$APP_NAME/Contents/MacOS/AllYouNeedQuickLook" 2>/dev/null || true
pkill -f "QuickLookExtension.appex" 2>/dev/null || true

step "Generating the project"
cd "$REPO"
xcodegen generate >/dev/null

step "Building Release"
DERIVED=$(mktemp -d /tmp/aynql-install.XXXXXX)
trap 'rm -rf "$DERIVED"' EXIT
xcodebuild -project "$PROJECT" -scheme AllYouNeedQuickLook \
    -configuration Release -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" build >"$DERIVED/build.log" 2>&1 \
    || { echo "build failed:"; tail -40 "$DERIVED/build.log"; exit 1; }

BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
[ -d "$BUILT" ] || { echo "no product at $BUILT" >&2; exit 1; }

step "Unregistering every known copy"
# Ghost records for directories that no longer exist are the whole problem, so
# unregister by path from the database rather than by what is on disk.
"$LSREGISTER" -dump 2>/dev/null \
    | grep -io "/[^ ]*AllYouNeedQuickLook[^ ]*\.app" \
    | sort -u \
    | while read -r path; do
        echo "    - $path"
        "$LSREGISTER" -u "$path" 2>/dev/null || true
    done

step "Replacing $INSTALLED"
rm -rf "$INSTALLED"
# ditto, not cp: it preserves the extended attributes the code signature
# lives in.
ditto "$BUILT" "$INSTALLED"

step "Verifying the installed signature"
codesign --verify --deep --strict "$INSTALLED" \
    && echo "    signature OK" \
    || { echo "    signature verification FAILED" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes" \
    "$INSTALLED/Contents/PlugIns/QuickLookExtension.appex/Contents/Info.plist"

if [ "$KEEP_DERIVED_DATA" -eq 0 ]; then
    step "Removing built copies from Xcode's DerivedData"
    find "$HOME/Library/Developer/Xcode/DerivedData" \
        -maxdepth 5 -type d -name "$APP_NAME" -path "*AllYouNeedQuickLook*" \
        -print -exec rm -rf {} + 2>/dev/null || true
fi

if [ "$RESET_CONFIG" -eq 1 ]; then
    step "Resetting settings"
    # load() falls back to the bundled default-config.json while no file
    # exists, so deleting it is the reset.
    if [ -f "$GROUP_CONTAINER/config.json" ]; then
        rm -f "$GROUP_CONTAINER/config.json"
        echo "    removed config.json"
    else
        echo "    no config.json; already at the bundled default"
    fi
fi

step "Registering the installed copy"
"$LSREGISTER" -f "$INSTALLED"
killall -u "$USER" quicklookd 2>/dev/null || true

step "Remaining registrations"
"$LSREGISTER" -dump 2>/dev/null \
    | grep -io "/[^ ]*AllYouNeedQuickLook[^ ]*\.app" | sort -u | sed 's/^/    /'

cat <<'DONE'

Done. Two things still need a human:

  1. Launch /Applications/AllYouNeedQuickLook.app once, so the extension is
     offered to the system.
  2. Enable it in System Settings > General > Login Items & Extensions >
     Quick Look, if it is not already on.

Then preview the corpus with Space in Finder.
DONE
