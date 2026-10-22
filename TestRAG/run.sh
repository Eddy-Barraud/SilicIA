#!/bin/sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_PATH="$SCRIPT_DIR/test"

DYLIB_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SilicIA-* -name "SilicIA.debug.dylib" 2>/dev/null | head -n 1)
if [ -z "$DYLIB_PATH" ]; then
    echo "❌ Error: Could not locate SilicIA.debug.dylib in DerivedData."
    echo "Please build SilicIA first: xcodebuild build -scheme SilicIA -destination platform=macOS"
    exit 1
fi

DYLIB_DIR="$(dirname "$DYLIB_PATH")"
DEBUG_PRODUCTS_DIR="$(cd "$DYLIB_DIR/../../.." && pwd)"

# Recompile only if binary is missing or test.swift is newer
if [ ! -f "$BIN_PATH" ] || [ "$SCRIPT_DIR/test.swift" -nt "$BIN_PATH" ] || [ "$DYLIB_PATH" -nt "$BIN_PATH" ]; then
    echo "🔨 Compiling TestRAG/test.swift against SilicIA..."
    swiftc "$SCRIPT_DIR/test.swift" \
        -parse-as-library \
        -I "$DEBUG_PRODUCTS_DIR" \
        "$DYLIB_PATH" \
        -Xlinker -rpath -Xlinker "$DYLIB_DIR" \
        -Xlinker -rpath -Xlinker "$DEBUG_PRODUCTS_DIR" \
        -Xfrontend -enable-testing \
        -o "$BIN_PATH"
fi

exec "$BIN_PATH" "$@"
