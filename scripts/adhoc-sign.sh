#!/bin/bash
# Ad-hoc sign the app bundle after the build.
#
# Why this exists instead of letting Xcode sign:
#
#   PlugInKit refuses to register an embedded app extension unless the host app
#   carries a real signature. With CODE_SIGNING_ALLOWED: NO the product has only
#   the linker's placeholder and `codesign -v` reports "code object is not signed
#   at all" -- the extension never appears in System Settings > Extensions.
#
#   Turning Xcode signing back on is not an option either: the App Group
#   entitlement makes the build system demand a provisioning profile
#   ("requires a provisioning profile. Enable development signing..."), which
#   would tie the project to one developer's team. `codesign` itself has no such
#   objection to an ad-hoc signature with those entitlements.
#
# So the build stays unsigned and this script signs inside-out afterwards:
# framework, then extension, then app. Signing the app first would be undone --
# each nested signature invalidates its container's.
set -euo pipefail

APP="${CODESIGNING_FOLDER_PATH:?must run from an Xcode build phase}"
FRAMEWORK="$APP/Contents/Frameworks/Shared.framework"
APPEX="$APP/Contents/PlugIns/QuickLookExtension.appex"

sign() {
    local target="$1" entitlements="${2:-}"
    [ -e "$target" ] || { echo "warning: $target missing, skipping"; return; }
    if [ -n "$entitlements" ]; then
        codesign --force --sign - --entitlements "$entitlements" --timestamp=none "$target"
    else
        codesign --force --sign - --timestamp=none "$target"
    fi
}

sign "$FRAMEWORK"
sign "$APPEX" "$SRCROOT/QuickLookExtension/QuickLookExtension.entitlements"
sign "$APP"   "$SRCROOT/AllYouNeedQuickLook/AllYouNeedQuickLook.entitlements"

codesign --verify --deep "$APP"
echo "ad-hoc signed: $APP"
