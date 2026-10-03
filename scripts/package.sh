#!/bin/bash
# 打包 Release 用的 zip：scripts/package.sh → build/DictTranslator-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
NO_INSTALL=1 ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP="build/DictTranslator-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/DictTranslator.app "$ZIP"
echo "==> $ZIP"
