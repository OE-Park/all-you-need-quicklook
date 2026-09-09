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

# Xcode 26 puts two helper Mach-Os next to the main binary in Contents/MacOS:
# the debug dylib that actually holds the code (`<name>.debug.dylib`) and the
# preview injection stub (`__preview.dylib`). On Apple Silicon the linker
# ad-hoc signs them on its own, so nobody notices them. On x86_64 -- which is
# what the GitHub macOS runner turned out to be -- it does not, and codesign
# refuses to sign a container whose nested code is unsigned:
#
#   QuickLookExtension.appex: code object is not signed at all
#   In subcomponent: .../QuickLookExtension.appex/Contents/MacOS/__preview.dylib
#
# So they get signed first, for the same inside-out reason as everything else
# here.
sign_nested_dylibs() {
    local bundle="$1" dylib
    for dylib in "$bundle"/Contents/MacOS/*.dylib; do
        [ -e "$dylib" ] || continue
        codesign --force --sign - --timestamp=none "$dylib"
    done
}

sign() {
    local target="$1" entitlements="${2:-}"
    [ -e "$target" ] || { echo "warning: $target missing, skipping"; return; }
    sign_nested_dylibs "$target"
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
