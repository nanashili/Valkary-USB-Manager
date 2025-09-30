# USB Device Manager for Zig

A cross-platform USB device detection library and daemon.

## Features

- **Cross-platform support**: Windows, Linux, and macOS
- **USB Daemon**: Real-time USB device monitoring with foreground/background modes
- **Cross-compilation**: Pre-built executables for all major platforms
- **Modular architecture**: Clean separation of concerns
- **Simple API**: Easy-to-use interface for listing USB devices
- **Zero dependencies**: Uses only Zig standard library
- **Memory safe**: Proper allocation and deallocation patterns

## Supported Platforms

| Platform | Command Used | Status |
|----------|-------------|--------|
| **Windows** | `wmic path CIM_LogicalDevice` | ✅ Supported |
| **Linux** | `lsusb -v` | ✅ Supported |
| **macOS** | `system_profiler SPUSBDataType` | ✅ Supported |

## USB Daemon

The USB daemon provides real-time monitoring of USB device changes (connect/disconnect events). It supports both foreground and background operation modes.

### Daemon Features

- **Real-time monitoring**: Detects USB device connect/disconnect events
- **Cross-platform**: Works on Windows, Linux, and macOS
- **Multiple modes**: Foreground (interactive) and background (service) modes
- **Configurable logging**: Production-ready log levels (error, warn, info, debug)
- **Signal handling**: Graceful shutdown with Ctrl+C
- **Production-ready**: Clean, structured logging suitable for deployment
- **Pre-built executables**: Ready-to-use binaries for all platforms

### Daemon Usage

```bash
# Show help
./usb-daemon --help

# Start in foreground mode (interactive)
./usb-daemon start-fg

# Start with specific log level (debug, info, warn, error)
./usb-daemon start-fg --log-level error    # Production (minimal output)
./usb-daemon start-fg --log-level info     # Standard operation
./usb-daemon start-fg --log-level debug    # Development/debugging

# Short form log level option
./usb-daemon start-fg -l debug

# Future: Background mode (daemon/service)
./usb-daemon start

# Future: Stop daemon
./usb-daemon stop

# Future: Check status
./usb-daemon status
```

### Log Levels

The daemon supports configurable log levels for production deployment:

| Level | Description | Use Case |
|-------|-------------|----------|
| **error** | Only critical errors | Production deployment |
| **warn** | Warnings and errors | Production with warnings |
| **info** | Standard operational messages | Default operation |
| **debug** | Detailed debugging information | Development/troubleshooting |

**Examples:**
```bash
# Production deployment - minimal output
./usb-daemon start-fg --log-level error

# Development - detailed output
./usb-daemon start-fg --log-level debug
```

### Pre-built Executables

Pre-compiled executables are available in the `release/` directory:

| Platform | Executable | Archive |
|----------|------------|---------|
| **macOS (Native)** | `release/macos-native/usb-daemon` | `usb-daemon-macos-native.tar.gz` |
| **Linux x86_64** | `release/linux-x86_64/usb-daemon` | `usb-daemon-linux-x86_64.tar.gz` |
| **Linux ARM64** | `release/linux-aarch64/usb-daemon` | `usb-daemon-linux-aarch64.tar.gz` |
| **Windows x86_64** | `release/windows-x86_64/usb-daemon.exe` | `usb-daemon-windows-x86_64.zip` |
| **Windows ARM64** | `release/windows-aarch64/usb-daemon.exe` | `usb-daemon-windows-aarch64.zip` |

## Requirements

- Zig 0.15.1 or later
- Platform-specific tools:
  - **Linux**: `lsusb` (usually pre-installed)
  - **macOS**: `system_profiler` (pre-installed)
  - **Windows**: `wmic` (pre-installed)

## Project Structure

```
usb-device-manager/
├── build.zig              # Build configuration
├── build.zig.zon          # Package manifest
├── README.md              # Documentation
├── LICENSE                # Apache 2.0 License
├── scripts/               # Build and utility scripts
│   ├── build-cross.sh     # Cross-compilation script (Unix)
│   └── build-cross.ps1    # Cross-compilation script (Windows)
├── release/               # Pre-built executables
│   ├── macos-native/      # macOS native executable
│   ├── linux-x86_64/     # Linux x86_64 executable
│   ├── linux-aarch64/    # Linux ARM64 executable
│   ├── windows-x86_64/   # Windows x86_64 executable
│   ├── windows-aarch64/  # Windows ARM64 executable
│   └── *.tar.gz, *.zip   # Distribution archives
└── src/
    ├── lib.zig            # Main library entry (re-exports)
    ├── usb_device.zig     # UsbDevice data structure
    ├── platform.zig       # Platform detection
    ├── collector.zig      # UsbDeviceCollector implementation
    ├── main.zig           # Example application
    ├── daemon.zig         # USB daemon implementation
    ├── daemon_main.zig    # Daemon entry point
    ├── monitor/           # Platform-specific monitoring
    │   └── mac_monitor.zig # macOS USB monitoring
    └── parser/
        ├── output_parser.zig    # Parser interface
        ├── empty_parser.zig     # Placeholder parser
        ├── windows_parser.zig   # Windows wmic parser
        ├── linux_parser.zig     # Linux lsusb parser
        └── mac_parser.zig       # macOS system_profiler parser
```

## Installation

### Using Zig Package Manager

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .@"usb-devices" = .{
        .url = "https://github.com/nanashili/Valkary-USB-Manager/archive/refs/tags/v0.0.1.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const usb_devices = b.dependency("usb-devices", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("usb-devices", usb_devices.module("usb-devices"));
```

### Manual Installation

Clone this repository and add it as a submodule or copy the `src/` directory into your project.

## Usage

### Basic Example

```zig
const std = @import("std");
const usb = @import("usb-devices");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var collector = usb.UsbDeviceCollector.init(allocator);

    // Check if platform is supported
    if (!collector.isSupported()) {
        std.debug.print("Platform not supported\n", .{});
        return;
    }

    // List all USB devices
    const devices = try collector.listUsbDevices();
    defer {
        for (devices) |*device| {
            var dev = device.*;
            dev.deinit(allocator);
        }
        allocator.free(devices);
    }

    // Print device information
    for (devices) |device| {
        std.debug.print("Device: {s}\n", .{device.name});
        std.debug.print("  Vendor ID: {s}\n", .{device.vendor_id});
        std.debug.print("  Product ID: {s}\n", .{device.product_id});
        if (device.serial_number) |sn| {
            std.debug.print("  Serial: {s}\n", .{sn});
        }
    }
}
```

### Advanced: Direct Parser Usage

If you need to parse USB device output directly without executing commands:

```zig
const std = @import("std");
const usb = @import("usb-devices");

pub fn parseCustomOutput(allocator: std.mem.Allocator, output: []const u8) ![]usb.UsbDevice {
    var parser = usb.parsers.OutputParser.fromPlatform(.linux);
    return try parser.parse(allocator, output);
}
```

### Platform-Specific Parsers

You can also use platform-specific parsers directly:

```zig
const usb = @import("usb-devices");

// Use Linux parser directly
var linux_parser = usb.parsers.LinuxParser{};
const devices = try linux_parser.parse(allocator, lsusb_output);

// Use Windows parser directly
var windows_parser = usb.parsers.WindowsParser{};
const devices = try windows_parser.parse(allocator, wmic_output);

// Use macOS parser directly
var mac_parser = usb.parsers.MacParser{};
const devices = try mac_parser.parse(allocator, profiler_output);
```

## API Reference

### Core Types

#### `UsbDevice`

Represents a USB device with its identifying information:

```zig
pub const UsbDevice = struct {
    name: []const u8,           // Device name
    vendor_id: []const u8,      // Vendor ID (e.g., "0x18d1")
    product_id: []const u8,     // Product ID (e.g., "0x4ee7")
    product_name: ?[]const u8,  // Optional product name
    serial_number: ?[]const u8, // Optional serial number
    device_id: ?[]const u8,     // Optional device ID (Windows)
    
    pub fn init(...) UsbDevice
    pub fn deinit(self: *UsbDevice, allocator: std.mem.Allocator) void
};
```

#### `Platform`

Platform enumeration and detection:

```zig
pub const Platform = enum {
    windows,
    linux,
    mac,
    unknown,
    
    pub fn current() Platform
    pub fn isSupported(self: Platform) bool
    pub fn getCommand(self: Platform, allocator: std.mem.Allocator) !?[]const u8
};
```

#### `UsbDeviceCollector`

Main interface for detecting USB devices:

```zig
pub const UsbDeviceCollector = struct {
    pub fn init(allocator: std.mem.Allocator) UsbDeviceCollector
    pub fn isSupported(self: *const UsbDeviceCollector) bool
    pub fn getPlatform(self: *const UsbDeviceCollector) Platform
    pub fn listUsbDevices(self: *UsbDeviceCollector) ![]UsbDevice
};
```

### Parser Types

#### `OutputParser`

Tagged union for platform-specific parsers:

```zig
pub const OutputParser = union(enum) {
    windows: WindowsParser,
    linux: LinuxParser,
    mac: MacParser,
    empty: EmptyParser,
    
    pub fn parse(self: *OutputParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice
    pub fn fromPlatform(platform: Platform) OutputParser
};
```

#### Platform-Specific Parsers

All parsers implement the same interface:

```zig
pub const WindowsParser = struct {
    pub fn parse(self: *WindowsParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice
};

pub const LinuxParser = struct {
    pub fn parse(self: *LinuxParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice
};

pub const MacParser = struct {
    pub fn parse(self: *MacParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice
};

pub const EmptyParser = struct {
    pub fn parse(self: *EmptyParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice
};
```

## Building

### Build the Library

```bash
zig build
```

### Run the Example

```bash
zig build run
```

### Run Tests

```bash
zig build test
```

### Build Options

```bash
# Release build
zig build -Doptimize=ReleaseFast

# Small release build
zig build -Doptimize=ReleaseSmall

# Safe release build
zig build -Doptimize=ReleaseSafe
```

## Cross-Compilation

The project supports cross-compilation for multiple platforms using automated build scripts.

### Quick Cross-Compilation

Use the provided scripts to build for all supported platforms:

**Unix/Linux/macOS:**
```bash
./scripts/build-cross.sh
```

**Windows (PowerShell):**
```powershell
.\scripts\build-cross.ps1
```

### Manual Cross-Compilation

Build for specific platforms manually:

```bash
# Windows x86_64
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast

# Windows ARM64
zig build -Dtarget=aarch64-windows -Doptimize=ReleaseFast

# Linux x86_64
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast

# Linux ARM64
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseFast

# macOS (native only - cross-compilation not supported due to framework dependencies)
zig build -Doptimize=ReleaseFast
```

### Cross-Compilation Targets

The build system supports the following cross-compilation targets:

| Target Platform | Architecture | Build Command | Output |
|------------------|--------------|---------------|---------|
| **Windows** | x86_64 | `zig build -Dtarget=x86_64-windows` | `usb-daemon-x86_64-windows.exe` |
| **Windows** | ARM64 | `zig build -Dtarget=aarch64-windows` | `usb-daemon-aarch64-windows.exe` |
| **Linux** | x86_64 | `zig build -Dtarget=x86_64-linux` | `usb-daemon-x86_64-linux` |
| **Linux** | ARM64 | `zig build -Dtarget=aarch64-linux` | `usb-daemon-aarch64-linux` |
| **macOS** | Native | `zig build` | `usb-daemon-native` |

**Note:** macOS cross-compilation is not supported due to framework dependencies (`IOKit`, `CoreFoundation`). macOS executables must be built natively on macOS systems.

## Example Output

```
USB Device Collector
====================

Platform: windows/mac/linux
Supported: true

Detecting USB devices...

Found 2 USB device(s):

Device 1:
  Name:       Apple Internal Keyboard / Trackpad
  Vendor ID:  0x05ac
  Product ID: 0x027e

Device 2:
  Name:       Google Nexus ADB Interface
  Vendor ID:  0x18d1
  Product ID: 0x4ee4
  Serial Number: HT7551A01234
  Device ID: VID_18D1&PID_4EE4\HT7551A01234

Device 3:
  Name:       Linux Foundation 3.0 root hub
  Vendor ID:  0x1d6b
  Product ID: 0x0003
```

## Memory Management

All USB device data is allocated on the heap. Remember to:

1. Call `deinit()` on each `UsbDevice` to free its memory
2. Free the device slice returned by `listUsbDevices()`

Example:
```zig
const devices = try collector.listUsbDevices();
defer {
    for (devices) |*device| {
        var dev = device.*;
        dev.deinit(allocator);
    }
    allocator.free(devices);
}
```

## Testing

Run all tests:
```bash
zig build test
```

The library includes unit tests for:
- Platform detection
- Device structure initialization
- Parser functionality (where testable without system commands)
- Memory management

## Contributing

Contributions are welcome! Please ensure:

1. Code follows Zig style guidelines
2. New modules are properly documented
3. Tests pass (`zig build test`)
4. Each module has a single, clear responsibility
5. Public APIs are documented with doc comments

## Limitations

- **Windows**: Serial numbers are only available for certain device types
- **Linux**: Requires `lsusb` command with `-v` flag (may need sudo for full info)
- **macOS**: Some USB hubs may not report all nested devices
- Command execution is synchronous (blocking)

## Troubleshooting

### Linux: "lsusb: command not found"

Install `usbutils`:
```bash
# Debian/Ubuntu
sudo apt-get install usbutils

# Fedora/RHEL
sudo dnf install usbutils

# Arch Linux
sudo pacman -S usbutils
```

### Linux: Limited device information

Run with elevated privileges:
```bash
sudo zig build run
```

### Windows: "wmic is deprecated"

The library works with both `wmic` and newer Windows systems. If you encounter issues, ensure you have administrative privileges.

## See Also

- [libusb](https://libusb.info/) - Full-featured USB library
- [Zig Standard Library](https://ziglang.org/documentation/master/std/) - Official documentation
