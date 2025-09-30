#!/bin/bash

# Cross-platform build script for USB Device Manager
# Builds executables for Windows, Linux, and macOS on both x86_64 and ARM64

set -e

# Change to project root directory (parent of scripts directory)
cd "$(dirname "$0")/.."

echo "🚀 Building USB Device Manager for all platforms..."
echo "=================================================="

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf zig-out/bin/*-*

# Build for all platforms
echo "🔨 Cross-compiling for all platforms..."
zig build cross -Doptimize=ReleaseFast

# Create release directory
RELEASE_DIR="release"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "📦 Packaging executables..."

# Package each platform executable
cd zig-out/bin

# Package Windows x86_64
if [ -f "usb-daemon-x86_64-windows.exe" ]; then
    echo "  📋 Packaging windows-x86_64..."
    mkdir -p "../../$RELEASE_DIR/windows-x86_64"
    cp usb-daemon-x86_64-windows.exe "../../$RELEASE_DIR/windows-x86_64/usb-daemon.exe"
fi

# Package Windows ARM64
if [ -f "usb-daemon-aarch64-windows.exe" ]; then
    echo "  📋 Packaging windows-aarch64..."
    mkdir -p "../../$RELEASE_DIR/windows-aarch64"
    cp usb-daemon-aarch64-windows.exe "../../$RELEASE_DIR/windows-aarch64/usb-daemon.exe"
fi

# Package Linux x86_64
if [ -f "usb-daemon-x86_64-linux" ]; then
    echo "  📋 Packaging linux-x86_64..."
    mkdir -p "../../$RELEASE_DIR/linux-x86_64"
    cp usb-daemon-x86_64-linux "../../$RELEASE_DIR/linux-x86_64/usb-daemon"
    chmod +x "../../$RELEASE_DIR/linux-x86_64/usb-daemon"
fi

# Package Linux ARM64
if [ -f "usb-daemon-aarch64-linux" ]; then
    echo "  📋 Packaging linux-aarch64..."
    mkdir -p "../../$RELEASE_DIR/linux-aarch64"
    cp usb-daemon-aarch64-linux "../../$RELEASE_DIR/linux-aarch64/usb-daemon"
    chmod +x "../../$RELEASE_DIR/linux-aarch64/usb-daemon"
fi

# Package macOS native
if [ -f "usb-daemon-native" ]; then
    echo "  📋 Packaging macos-native..."
    mkdir -p "../../$RELEASE_DIR/macos-native"
    cp usb-daemon-native "../../$RELEASE_DIR/macos-native/usb-daemon"
    chmod +x "../../$RELEASE_DIR/macos-native/usb-daemon"
fi

# Return to project root
cd ../..

# Create archives for each platform
echo "📦 Creating archives..."

# Store current directory
CURRENT_DIR=$(pwd)

for platform_dir in "$RELEASE_DIR"/*/; do
    if [ -d "$platform_dir" ]; then
        platform_name=$(basename "$platform_dir")
        echo "  🗜️  Creating archive for $platform_name..."
        
        cd "$RELEASE_DIR"
        case "$platform_name" in
            windows-*)
                zip -r "usb-daemon-$platform_name.zip" "$platform_name/"
                ;;
            *)
                tar -czf "usb-daemon-$platform_name.tar.gz" "$platform_name/"
                ;;
        esac
        cd "$CURRENT_DIR"
    fi
done

echo "✅ Cross-compilation complete!"
echo ""
echo "📁 Available executables:"
ls -la "$RELEASE_DIR"

echo ""
echo "🎯 Platform-specific executables:"
find "$RELEASE_DIR" -name "usb-daemon*" -type f | sort

echo ""
echo "📖 Usage:"
echo "  Extract the appropriate archive for your platform"
echo "  Run: ./usb-daemon --help"
echo ""
echo "🌍 Supported platforms:"
echo "  • Windows x86_64"
echo "  • Linux x86_64"
echo "  • Linux ARM64"
echo "  • macOS x86_64 (Intel)"
echo "  • macOS ARM64 (Apple Silicon)"