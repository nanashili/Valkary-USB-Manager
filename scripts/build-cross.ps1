# Cross-platform build script for USB Device Manager (PowerShell)
# Builds executables for Windows, Linux, and macOS on both x86_64 and ARM64

param(
    [switch]$Clean = $false
)

# Change to project root directory (parent of scripts directory)
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "🚀 Building USB Device Manager for all platforms..." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green

# Clean previous builds if requested
if ($Clean) {
    Write-Host "🧹 Cleaning previous builds..." -ForegroundColor Yellow
    if (Test-Path "zig-out\bin") {
        Get-ChildItem "zig-out\bin" -Directory | Where-Object { $_.Name -match "-" } | Remove-Item -Recurse -Force
    }
}

# Build for all platforms
Write-Host "🔨 Cross-compiling for all platforms..." -ForegroundColor Cyan
try {
    & zig build cross -Doptimize=ReleaseFast
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "❌ Build failed: $_" -ForegroundColor Red
    exit 1
}

# Create release directory
$ReleaseDir = "release"
if (Test-Path $ReleaseDir) {
    Remove-Item $ReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ReleaseDir | Out-Null

Write-Host "📦 Packaging executables..." -ForegroundColor Cyan

# Package each platform
$PlatformDirs = Get-ChildItem "zig-out\bin" -Directory | Where-Object { $_.Name -match "-" }

foreach ($PlatformDir in $PlatformDirs) {
    $PlatformName = $PlatformDir.Name
    Write-Host "  📋 Packaging $PlatformName..." -ForegroundColor White
    
    # Create platform-specific directory
    $PlatformPath = Join-Path $ReleaseDir $PlatformName
    New-Item -ItemType Directory -Path $PlatformPath | Out-Null
    
    # Copy executable
    Copy-Item "$($PlatformDir.FullName)\*" $PlatformPath -Recurse
    
    # Add .exe extension for Windows executables
    if ($PlatformName -match "windows") {
        Get-ChildItem $PlatformPath -File | ForEach-Object {
            if ($_.Extension -ne ".exe") {
                Rename-Item $_.FullName "$($_.Name).exe"
            }
        }
    }
    
    # Create archive
    Push-Location $ReleaseDir
    try {
        if ($PlatformName -match "windows") {
            Compress-Archive -Path $PlatformName -DestinationPath "usb-daemon-$PlatformName.zip" -Force
        } else {
            # Use tar if available, otherwise use zip
            if (Get-Command tar -ErrorAction SilentlyContinue) {
                & tar -czf "usb-daemon-$PlatformName.tar.gz" $PlatformName
            } else {
                Compress-Archive -Path $PlatformName -DestinationPath "usb-daemon-$PlatformName.zip" -Force
            }
        }
    } finally {
        Pop-Location
    }
}

Write-Host "✅ Cross-compilation complete!" -ForegroundColor Green
Write-Host ""

Write-Host "📁 Available executables:" -ForegroundColor Cyan
Get-ChildItem $ReleaseDir | Format-Table Name, Length, LastWriteTime

Write-Host ""
Write-Host "🎯 Platform-specific executables:" -ForegroundColor Cyan
Get-ChildItem $ReleaseDir -Recurse -File | Where-Object { $_.Name -match "usb-daemon" } | Sort-Object FullName | ForEach-Object {
    Write-Host "  $($_.FullName)" -ForegroundColor White
}

Write-Host ""
Write-Host "📖 Usage:" -ForegroundColor Yellow
Write-Host "  Extract the appropriate archive for your platform"
Write-Host "  Run: .\usb-daemon.exe --help (Windows) or ./usb-daemon --help (Unix)"
Write-Host ""
Write-Host "🌍 Supported platforms:" -ForegroundColor Yellow
Write-Host "  • Windows x86_64"
Write-Host "  • Linux x86_64"
Write-Host "  • Linux ARM64"
Write-Host "  • macOS x86_64 (Intel)"
Write-Host "  • macOS ARM64 (Apple Silicon)"