#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
xcodebuild -project VoilaxaChat.xcodeproj -scheme VoilaxaChat -configuration Release -destination 'generic/platform=iOS' -archivePath "$PWD/build/VoilaxaChat.xcarchive" archive
cp ExportOptions.plist.example build/ExportOptions.plist
xcodebuild -exportArchive -archivePath "$PWD/build/VoilaxaChat.xcarchive" -exportPath "$PWD/build/export" -exportOptionsPlist "$PWD/build/ExportOptions.plist"
echo "IPA : $PWD/build/export"
