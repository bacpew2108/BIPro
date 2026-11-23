#!/bin/zsh
# Builds "BI Pro.app" (v1.3.0) from SwiftPM + native AppIcon.icns + Quick Look .appex extensions (no Xcode required).
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${1:-release}"
APP="$ROOT/build/BI Pro.app"

cd "$ROOT"
swift build --disable-sandbox -c "$CONFIG" --product BIPro
BIN_DIR="$(swift build --disable-sandbox -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/BIPro"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns"
cp "$BIN" "$APP/Contents/MacOS/BIPro"

# 1. Native App Icon (CoreGraphics + iconutil/ICNS)
swift "$ROOT/scripts/make-icon.swift" "$APP/Contents/Resources/AppIcon.icns"

# 2. Host Info.plist (v1.0.0)
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.bipro.app</string>
    <key>CFBundleName</key><string>BI Pro</string>
    <key>CFBundleDisplayName</key><string>BI Pro</string>
    <key>CFBundleExecutable</key><string>BIPro</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.3.0</string>
    <key>CFBundleVersion</key><string>130</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.business</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Power BI Report</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Default</string>
            <key>LSItemContentTypes</key><array><string>com.microsoft.powerbi.pbix</string></array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.microsoft.powerbi.pbix</string>
            <key>UTTypeDescription</key><string>Power BI Report</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key><array><string>pbix</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# 3. Quick Look Preview & Thumbnail Extensions (.appex) linked against PBIXKit + CXPress9
SDK="$(xcrun --show-sdk-path)"
PBIX_OBJS=("$BIN_DIR/PBIXKit.build"/*.o "$BIN_DIR/CXPress9.build"/*.o)
EXT_ENT="$ROOT/build/ql-ext-entitlements.plist"
cat > "$EXT_ENT" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
</dict>
</plist>
ENT

build_appex() {
    local NAME="$1"
    local SRC="$2"
    local BUNDLE_ID="$3"
    local EXT_POINT="$4"
    local PRINCIPAL="$5"
    local FRAMEWORK="$6"
    local EXTRA_PLIST="$7"
    local APPEX="$APP/Contents/PlugIns/$NAME.appex"

    mkdir -p "$APPEX/Contents/MacOS"
    swiftc \
        -sdk "$SDK" \
        -target arm64-apple-macosx15.0 \
        -parse-as-library \
        -application-extension \
        -I "$BIN_DIR/Modules" \
        -Xcc -fmodule-map-file="$BIN_DIR/CXPress9.build/module.modulemap" \
        "$SRC" \
        "${PBIX_OBJS[@]}" \
        -lsqlite3 \
        -framework Foundation \
        -framework AppKit \
        -framework CoreGraphics \
        -framework CoreText \
        -framework "$FRAMEWORK" \
        -Xlinker -e -Xlinker _NSExtensionMain \
        -o "$APPEX/Contents/MacOS/$NAME"

    cat > "$APPEX/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>1.3.0</string>
    <key>CFBundleVersion</key><string>130</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>$EXT_POINT</string>
        <key>NSExtensionPrincipalClass</key><string>$PRINCIPAL</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLSupportedContentTypes</key>
            <array><string>com.microsoft.powerbi.pbix</string></array>
$EXTRA_PLIST
        </dict>
    </dict>
</dict>
</plist>
EOF
    codesign --force --sign - --entitlements "$EXT_ENT" "$APPEX" >/dev/null
}

build_appex \
    "PBIXQuickLook" \
    "$ROOT/Sources/PBIXQuickLook/PreviewViewController.swift" \
    "local.bipro.app.quicklook" \
    "com.apple.quicklook.preview" \
    "PBIXPreviewViewController" \
    "QuickLookUI" \
    "            <key>QLSupportsSearchableItems</key><false/>"

build_appex \
    "PBIXThumbnail" \
    "$ROOT/Sources/PBIXQuickLook/ThumbnailProvider.swift" \
    "local.bipro.app.thumbnail" \
    "com.apple.quicklook.thumbnail" \
    "PBIXThumbnailProvider" \
    "QuickLookThumbnailing" \
    "            <key>QLThumbnailMinimumDimension</key><integer>32</integer>"

rm -f "$EXT_ENT"

# Sign host app after embedded PlugIns
codesign --force --sign - "$APP" >/dev/null
# Register app & extensions with Launch Services / PlugInKit (ignore non-fatal errors in restricted shells)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
pluginkit -a "$APP/Contents/PlugIns/PBIXQuickLook.appex" 2>/dev/null || true
pluginkit -a "$APP/Contents/PlugIns/PBIXThumbnail.appex" 2>/dev/null || true
echo "Built: $APP (v1.3.0)"
