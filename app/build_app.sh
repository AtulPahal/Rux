#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Building Rux macOS Application ==="

# 1. Build Rust workspace in release mode
echo "[1/5] Building Rux Rust toolchain in release mode..."
cargo build --release --workspace

# 2. Ensure AppIcon.icns exists
if [ ! -f "${SCRIPT_DIR}/Resources/AppIcon.icns" ]; then
    echo "[2/5] Generating AppIcon.icns..."
    python3 "${SCRIPT_DIR}/generate_icon.py"
else
    echo "[2/5] AppIcon.icns already present."
fi

# 3. Compile native Swift AppKit GUI
echo "[3/5] Compiling Swift AppKit application..."
BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

swiftc -O \
    "${SCRIPT_DIR}/Sources"/*.swift \
    "${SCRIPT_DIR}/Sources/UI"/*.swift \
    -o "${BUILD_DIR}/Rux"

# 4. Construct Rux.app bundle
APP_BUNDLE="${ROOT_DIR}/Rux.app"
echo "[4/5] Assembling bundle: ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Helpers"

# Copy Info.plist
cp "${SCRIPT_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy Main Executable
cp "${BUILD_DIR}/Rux" "${APP_BUNDLE}/Contents/MacOS/Rux"
chmod +x "${APP_BUNDLE}/Contents/MacOS/Rux"

# Copy Bundled CLI Tools into Contents/MacOS and Contents/Helpers
cp "${ROOT_DIR}/target/release/rux" "${APP_BUNDLE}/Contents/MacOS/rux-cli"
cp "${ROOT_DIR}/target/release/rux" "${APP_BUNDLE}/Contents/Helpers/rux"
cp "${ROOT_DIR}/target/release/inject" "${APP_BUNDLE}/Contents/MacOS/inject"
cp "${ROOT_DIR}/target/release/injectarm" "${APP_BUNDLE}/Contents/MacOS/injectarm"
chmod +x "${APP_BUNDLE}/Contents/MacOS/rux-cli" "${APP_BUNDLE}/Contents/Helpers/rux" "${APP_BUNDLE}/Contents/MacOS/inject" "${APP_BUNDLE}/Contents/MacOS/injectarm"

# Copy Bundled Frameworks & Payload Dylibs
cp "${ROOT_DIR}/target/release/libmachinject.dylib" "${APP_BUNDLE}/Contents/Frameworks/libmachinject.dylib"
cp "${ROOT_DIR}/target/release/librux_payload.dylib" "${APP_BUNDLE}/Contents/Frameworks/exploit.dylib"
cp "${ROOT_DIR}/target/release/librux_payload.dylib" "${APP_BUNDLE}/Contents/Frameworks/librux_payload.dylib"

# Copy Resources (Icons, duplicate dylibs for lookup fallback)
cp "${SCRIPT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "${ROOT_DIR}/target/release/librux_payload.dylib" "${APP_BUNDLE}/Contents/Resources/exploit.dylib"
cp "${ROOT_DIR}/target/release/librux_payload.dylib" "${APP_BUNDLE}/Contents/Resources/librux_payload.dylib"
cp "${ROOT_DIR}/target/release/libmachinject.dylib" "${APP_BUNDLE}/Contents/Resources/libmachinject.dylib"
cp "${ROOT_DIR}/target/release/rux" "${APP_BUNDLE}/Contents/Resources/rux"

# 5. Ad-hoc codesign the bundle
echo "[5/5] Codesigning bundle with ad-hoc signature..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
echo "=========================================================="
echo "  [SUCCESS] Rux.app successfully created at:"
echo "  ${APP_BUNDLE}"
echo "=========================================================="
echo "To launch: open ${APP_BUNDLE}"
