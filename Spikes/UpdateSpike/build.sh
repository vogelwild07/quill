#!/bin/zsh
# Baut UpdateSpike.app in Version $1 nach $2, ad hoc signiert mit Hardened Runtime wie
# make-release.sh. $SPARKLE zeigt auf das entpackte Sparkle-2.x (Ordner mit Sparkle.framework).
# $FEED und $PUBKEY gehen ins Info.plist.
set -eu
version=$1; out=$2
here=${0:A:h}
app=$out/UpdateSpike.app
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp -R "$SPARKLE/Sparkle.framework" "$app/Contents/Frameworks/"
swiftc -O -swift-version 6 -target arm64-apple-macos26.0 -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$app/Contents/MacOS/UpdateSpike" "$here/Sources/main.swift" "$here/Sources/SpikeUserDriver.swift"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>io.github.vogelwild07.quill.updatespike</string>
	<key>CFBundleName</key><string>UpdateSpike</string>
	<key>CFBundleExecutable</key><string>UpdateSpike</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>$version</string>
	<key>CFBundleShortVersionString</key><string>0.$version</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>SUFeedURL</key><string>$FEED</string>
	<key>SUPublicEDKey</key><string>$PUBKEY</string>
	<key>SUEnableInstallerLauncherService</key><true/>
	<key>SUEnableAutomaticChecks</key><true/>
	<key>SpikePostpone</key><${POSTPONE:-false}/>
	<key>SpikeOwnDriver</key><${OWN_DRIVER:-false}/>
	<key>SpikeBackupFails</key><${BACKUP_FAILS:-false}/>
$( [ "${LOCAL_ATS:-true}" = true ] && echo '	<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>' )
</dict>
</plist>
PLIST
fw=$app/Contents/Frameworks/Sparkle.framework/Versions/B
codesign -f -s - -o runtime "$fw/XPCServices/Installer.xpc"
codesign -f -s - -o runtime --preserve-metadata=entitlements "$fw/XPCServices/Downloader.xpc"
codesign -f -s - -o runtime "$fw/Autoupdate"
codesign -f -s - -o runtime "$fw/Updater.app"
codesign -f -s - -o runtime "$app/Contents/Frameworks/Sparkle.framework"
codesign -f -s - -o runtime --entitlements "$here/UpdateSpike.entitlements" "$app"
codesign --verify --deep --strict "$app"
