#!/bin/zsh
# Збирання Помітки без Xcode (досить Command Line Tools):
#   ./build.sh          — перевірка + збирання build/Pomitka.app (Apple Silicon і Intel в одному файлі)
#   ./build.sh install  — те саме + копія в ~/Applications і перезапуск програми
#   ./build.sh dist     — те саме + архів для завантаження: dist/Pomitka-<версія>.zip
set -euo pipefail
cd "${0:A:h}"

APP=build/Pomitka.app
SOURCES=(Sources/Core.swift Sources/App/Editor.swift Sources/App/main.swift)
FRAMEWORKS=(-framework AppKit -framework CoreImage -framework ServiceManagement)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Перевірка: малює позначки на штучному знімку → build/sample.png, вікно → build/window.png
swiftc -swift-version 5 -O Sources/Core.swift Sources/App/Editor.swift Tests/main.swift -o build/selftest \
    -framework AppKit -framework CoreImage
build/selftest build

# Окремо під кожен процесор, потім — один спільний файл
for arch in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" "${SOURCES[@]}" -o "build/Pomitka-$arch" "${FRAMEWORKS[@]}"
done
lipo -create build/Pomitka-arm64 build/Pomitka-x86_64 -output "$APP/Contents/MacOS/Pomitka"
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign -s - --force "$APP"   # локальний підпис без сертифіката Apple
echo "Зібрано: $PWD/$APP ($(lipo -archs "$APP/Contents/MacOS/Pomitka"), версія $VERSION)"

case "${1:-}" in
install)
    pkill -x Pomitka || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Pomitka.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Pomitka.app
    echo "Встановлено й запущено: ~/Applications/Pomitka.app"
    ;;
dist)
    mkdir -p dist
    rm -f "dist/Pomitka-$VERSION.zip"
    ditto -c -k --keepParent "$APP" "dist/Pomitka-$VERSION.zip"
    echo "Архів: $PWD/dist/Pomitka-$VERSION.zip"
    ;;
esac
