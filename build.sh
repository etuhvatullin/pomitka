#!/bin/zsh
# Збирання Помітки без Xcode (досить Command Line Tools):
#   ./build.sh          — перевірка + збирання build/Pomitka.app
#   ./build.sh install  — те саме + копія в ~/Applications і перезапуск програми
set -euo pipefail
cd "${0:A:h}"

APP=build/Pomitka.app
SWIFTC=(swiftc -swift-version 5 -O -target arm64-apple-macos13.0)

rm -rf build && mkdir -p "$APP/Contents/MacOS"

# Перевірка: малює позначки на штучному знімку → build/sample.png, вікно → build/window.png
"${SWIFTC[@]}" Sources/Core.swift Sources/App/Editor.swift Tests/main.swift -o build/selftest \
    -framework AppKit -framework CoreImage
build/selftest build

"${SWIFTC[@]}" Sources/Core.swift Sources/App/Editor.swift Sources/App/main.swift \
    -o "$APP/Contents/MacOS/Pomitka" -framework AppKit -framework CoreImage -framework ServiceManagement
cp Info.plist "$APP/Contents/"
codesign -s - --force "$APP"   # локальний підпис без сертифіката
echo "Зібрано: $PWD/$APP"

if [[ "${1:-}" == install ]]; then
    pkill -x Pomitka || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Pomitka.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Pomitka.app
    echo "Встановлено й запущено: ~/Applications/Pomitka.app"
fi
