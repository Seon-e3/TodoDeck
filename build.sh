#!/bin/zsh
# TodoDeck.app 빌드. 실행: ./build.sh && open TodoDeck.app
set -e
cd "$(dirname "$0")"
swift build -c release
rm -rf TodoDeck.app
mkdir -p TodoDeck.app/Contents/MacOS
cp .build/release/TodoDeck TodoDeck.app/Contents/MacOS/
cp Info.plist TodoDeck.app/Contents/
codesign -s - --force TodoDeck.app
echo "built TodoDeck.app"
