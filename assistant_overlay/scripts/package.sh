#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="assistant_overlay"
BUILD_TYPE=${BUILD_TYPE:-release}

echo "Building $PROJECT_NAME ($BUILD_TYPE)..."
cd "$PROJECT_DIR"
flutter build macos --$BUILD_TYPE

APP_PATH="build/macos/Build/Products/$BUILD_TYPE/$PROJECT_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

OUTPUT_DMG="${PROJECT_NAME}.dmg"
echo "Creating DMG: $OUTPUT_DMG"
create-dmg \
    --volname "$PROJECT_NAME" \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 200 \
    "$OUTPUT_DMG" \
    "$APP_PATH"

echo "Done: $OUTPUT_DMG"