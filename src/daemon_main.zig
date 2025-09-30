const std = @import("std");
const daemon = @import("daemon.zig");
const UsbDevice = @import("usb_device.zig").UsbDevice;

/// Log level configuration
const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    
    pub fn fromString(str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, str, "debug")) {
            return .debug;
        } else if (std.mem.eql(u8, str, "info")) {
            return .info;
        } else if (std.mem.eql(u8, str, "warn")) {
            return .warn;
        } else if (std.mem.eql(u8, str, "error")) {
            return .err;
        }
        return null;
    }
};

/// Global log level setting
var global_log_level: LogLevel = .info;

/// Command line arguments structure
const Args = struct {
    command: Command,
    log_level: LogLevel = .info,
    help: bool = false,
    
    const Command = enum {
        help,
        start_fg,
        start,
        stop,
        status,
        
        pub fn fromString(str: []const u8) ?Command {
            if (std.mem.eql(u8, str, "help") or std.mem.eql(u8, str, "--help") or std.mem.eql(u8, str, "-h")) {
                return .help;
            } else if (std.mem.eql(u8, str, "start-fg")) {
                return .start_fg;
            } else if (std.mem.eql(u8, str, "start")) {
                return .start;
            } else if (std.mem.eql(u8, str, "stop")) {
                return .stop;
            } else if (std.mem.eql(u8, str, "status")) {
                return .status;
            }
            return null;
        }
    };
};

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !Args {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        return Args{ .command = .help };
    }
    
    var result = Args{ .command = .help };
    
    // Parse command
    const command_str = args[1];
    result.command = Args.Command.fromString(command_str) orelse .help;
    
    // Parse additional arguments
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--log-level") or std.mem.eql(u8, arg, "-l")) {
            if (i + 1 < args.len) {
                i += 1;
                result.log_level = LogLevel.fromString(args[i]) orelse .info;
            }
        }
    }
    
    return result;
}

/// Print help message
fn printHelp() void {
    std.debug.print(
        \\USB Device Daemon
        \\================
        \\
        \\A cross-platform USB device monitoring daemon that detects device connect/disconnect events.
        \\
        \\USAGE:
        \\    usb-daemon <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    start-fg    Start daemon in foreground mode (interactive)
        \\    start       Start daemon in background mode (future feature)
        \\    stop        Stop running daemon (future feature)
        \\    status      Check daemon status (future feature)
        \\    help        Show this help message
        \\
        \\OPTIONS:
        \\    --log-level, -l <LEVEL>    Set log level (debug, info, warn, error) [default: info]
        \\
        \\EXAMPLES:
        \\    usb-daemon start-fg                    # Start monitoring in foreground
        \\    usb-daemon start-fg --log-level debug # Start with debug logging
        \\    usb-daemon start-fg -l error          # Start with error-only logging
        \\    usb-daemon --help                     # Show help
        \\
        \\SUPPORTED PLATFORMS:
        \\    • Windows (polling-based monitoring)
        \\    • Linux (polling-based monitoring)
        \\    • macOS (IOKit-based real-time monitoring)
        \\
        \\NOTES:
        \\    - Use Ctrl+C to stop the daemon gracefully
        \\    - Background mode and daemon management features are planned for future releases
        \\    - On macOS, real-time monitoring uses IOKit notifications
        \\    - On Linux/Windows, monitoring uses periodic polling (1-second intervals)
        \\    - Log levels: debug (verbose), info (default), warn (warnings only), error (errors only)
        \\
    , .{});
}

/// Device event callback function
/// Handle device events for foreground mode
fn onDeviceEvent(event: daemon.DeviceEvent, device: ?daemon.UsbDevice) void {
    const timestamp = std.time.timestamp();
    const seconds_in_day = @mod(timestamp, 86400);
    const hours = @divTrunc(seconds_in_day, 3600);
    const minutes = @divTrunc(@mod(seconds_in_day, 3600), 60);
    const seconds = @mod(seconds_in_day, 60);
    
    switch (event) {
        .connected => {
            if (device) |dev| {
                std.log.info("[{:02}:{:02}:{:02}] Device connected: {s} (VID: {s}, PID: {s})", .{
                    hours, minutes, seconds, dev.name, dev.vendor_id, dev.product_id
                });
            } else {
                std.log.info("[{:02}:{:02}:{:02}] Device connected: Unknown device", .{ hours, minutes, seconds });
            }
        },
        .disconnected => {
            if (device) |dev| {
                std.log.info("[{:02}:{:02}:{:02}] Device disconnected: {s} (VID: {s}, PID: {s})", .{
                    hours, minutes, seconds, dev.name, dev.vendor_id, dev.product_id
                });
            } else {
                std.log.info("[{:02}:{:02}:{:02}] Device disconnected: Unknown device", .{ hours, minutes, seconds });
            }
        },
        .err => {
            std.log.err("[{:02}:{:02}:{:02}] USB monitoring error occurred", .{ hours, minutes, seconds });
        },
    }
}

/// Start daemon in foreground mode
fn startForeground(allocator: std.mem.Allocator, log_level: LogLevel) !void {
    global_log_level = log_level;
    
    var monitor = daemon.UsbDeviceMonitor.init(allocator);
    defer monitor.deinit();
    
    // Set up signal handler for graceful shutdown
    try daemon.setupSignalHandler(&monitor);
    
    std.log.info("USB Device Daemon starting on platform: {any}", .{monitor.getPlatform()});
    
    if (!monitor.getPlatform().isSupported()) {
        std.log.err("USB monitoring is not supported on this platform", .{});
        return;
    }
    
    // Get initial device count
    const initial_devices = monitor.collector.listUsbDevices() catch |err| {
        std.log.err("Failed to get initial device list: {}", .{err});
        return;
    };
    defer {
        for (initial_devices) |*device| {
            device.deinit(allocator);
        }
        allocator.free(initial_devices);
    }
    
    std.log.info("Currently connected devices: {}", .{initial_devices.len});
    if (global_log_level == .debug) {
        for (initial_devices, 0..) |device, i| {
            std.log.debug("  {}. {s} (VID: {s}, PID: {s})", .{ i + 1, device.name, device.vendor_id, device.product_id });
        }
    }
    
    std.log.info("Starting USB device monitoring...", .{});
    
    // Start monitoring
    monitor.start(onDeviceEvent) catch |err| {
        std.log.err("Failed to start monitor: {}", .{err});
        return;
    };
    
    std.log.info("USB daemon stopped gracefully", .{});
}

/// Main entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = parseArgs(allocator) catch |err| {
        std.log.err("Error parsing arguments: {}", .{err});
        return;
    };
    
    // Set global log level
    global_log_level = args.log_level;
    
    switch (args.command) {
        .help => printHelp(),
        .start_fg => {
            startForeground(allocator, args.log_level) catch |err| {
                std.log.err("Daemon error: {}", .{err});
                std.process.exit(1);
            };
        },
        .start => {
            std.log.err("Background mode is not yet implemented", .{});
            if (args.log_level == .debug or args.log_level == .info) {
                std.log.info("Use 'start-fg' for foreground mode", .{});
            }
            std.process.exit(1);
        },
        .stop => {
            std.log.err("Daemon management is not yet implemented", .{});
            if (args.log_level == .debug or args.log_level == .info) {
                std.log.info("Use Ctrl+C to stop a running foreground daemon", .{});
            }
            std.process.exit(1);
        },
        .status => {
            std.log.err("Status checking is not yet implemented", .{});
            std.process.exit(1);
        },
    }
}