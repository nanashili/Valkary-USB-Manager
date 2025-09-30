const std = @import("std");
const daemon = @import("daemon.zig");
const UsbDevice = @import("usb_device.zig").UsbDevice;
const logger = @import("logger.zig");

/// Use LogLevel from logger module
const LogLevel = logger.LogLevel;

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
fn onDeviceEvent(monitor: *daemon.UsbDeviceMonitor, event: daemon.DeviceEvent, device: ?daemon.UsbDevice) void {
    const timestamp = std.time.timestamp();
    const seconds_in_day = @mod(timestamp, 86400);
    const hours = @divTrunc(seconds_in_day, 3600);
    const minutes = @divTrunc(@mod(seconds_in_day, 3600), 60);
    const seconds = @mod(seconds_in_day, 60);
    
    switch (event) {
        .connected => {
            if (device) |dev| {
                logger.info("[{:02}:{:02}:{:02}] Device connected: {s} (VID: {s}, PID: {s})", .{
                     hours, minutes, seconds, dev.name, dev.vendor_id, dev.product_id
                 });
    } else {
        logger.info("[{:02}:{:02}:{:02}] Device connected: Unknown device", .{ hours, minutes, seconds });
            }
        },
        .disconnected => {
            if (device) |dev| {
                logger.info("[{:02}:{:02}:{:02}] Device disconnected: {s} (VID: {s}, PID: {s})", .{
                    hours, minutes, seconds, dev.name, dev.vendor_id, dev.product_id
                });
            } else {
                logger.info("[{:02}:{:02}:{:02}] Device disconnected: Unknown device", .{ hours, minutes, seconds });
            }
        },
        .err => {
            logger.err("[{:02}:{:02}:{:02}] USB monitoring error occurred", .{ hours, minutes, seconds });
        },
    }
    
    // Get and display current device count after each event
    const current_devices = monitor.collector.listUsbDevices() catch |err| {
        logger.err("Failed to get current device list: {}", .{err});
        return;
    };
    defer {
        for (current_devices) |*dev| {
            dev.deinit(monitor.allocator);
        }
        monitor.allocator.free(current_devices);
    }
    
    logger.info("Currently connected devices: {}", .{current_devices.len});
}

/// Start daemon in foreground mode
fn startForeground(allocator: std.mem.Allocator, log_level: LogLevel) !void {
    logger.setLogLevel(log_level);
    
    var monitor = daemon.UsbDeviceMonitor.init(allocator);
    defer monitor.deinit();
    
    // Set up signal handler for graceful shutdown
    try daemon.setupSignalHandler(&monitor);
    
    logger.info("USB Device Daemon starting on platform: {any}", .{monitor.getPlatform()});
    
    if (!monitor.platform.isSupported()) {
        logger.err("USB monitoring is not supported on this platform", .{});
        return;
    }
    
    // Get initial device list
    const initial_devices = monitor.collector.listUsbDevices() catch |err| {
        logger.err("Failed to get initial device list: {}", .{err});
        return;
    };
    defer {
        for (initial_devices) |*device| {
            device.deinit(allocator);
        }
        allocator.free(initial_devices);
    }
    
    logger.info("Currently connected devices: {}", .{initial_devices.len});
    for (initial_devices, 0..) |device, i| {
        logger.debug("  {}. {s} (VID: {s}, PID: {s})", .{ i + 1, device.name, device.vendor_id, device.product_id });
    }
    
    logger.info("Starting USB device monitoring...", .{});
    
    // Start monitoring with our callback
    monitor.start(onDeviceEvent) catch |err| {
        logger.err("Failed to start monitor: {}", .{err});
        return;
    };
    
    logger.info("USB daemon stopped gracefully", .{});
}

/// Main entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = parseArgs(allocator) catch |err| {
        logger.err("Error parsing arguments: {}", .{err});
        return;
    };
    
    // Set global log level
    logger.setLogLevel(args.log_level);
    
    switch (args.command) {
        .help => printHelp(),
        .start_fg => {
            startForeground(allocator, args.log_level) catch |err| {
                logger.err("Daemon error: {}", .{err});
                std.process.exit(1);
            };
        },
        .start => {
            logger.err("Background mode is not yet implemented", .{});
            if (args.log_level == .debug or args.log_level == .info) {
                logger.info("Use 'start-fg' for foreground mode", .{});
            }
            std.process.exit(1);
        },
        .stop => {
            logger.err("Daemon management is not yet implemented", .{});
            if (args.log_level == .debug or args.log_level == .info) {
                logger.info("Use Ctrl+C to stop a running foreground daemon", .{});
            }
            std.process.exit(1);
        },
        .status => {
            logger.err("Status checking is not yet implemented", .{});
            std.process.exit(1);
        },
    }
}