#!/bin/zsh
# Builds "BI Pro.app" from the SwiftPM executable (no Xcode required).
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${1:-release}"
APP="$ROOT/build/BI Pro.app"

cd "$ROOT"
swift build -c "$CONFIG" --product BIPro
BIN="$(swift build -c "$CONFIG" --show-bin-path)/BIPro"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BIPro"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.bipro.app</string>
    <key>CFBundleName</key><string>BI Pro</string>
    <key>CFBundleDisplayName</key><string>BI Pro</string>
    <key>CFBundleExecutable</key><string>BIPro</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.business</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Power BI Report</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
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

codesign --force --sign - "$APP" >/dev/null
# Register the document type with Launch Services so Finder offers the app for .pbix.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built: $APP"
