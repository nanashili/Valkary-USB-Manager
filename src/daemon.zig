const std = @import("std");
pub const UsbDevice = @import("usb_device.zig").UsbDevice;
const UsbDeviceCollector = @import("collector.zig").UsbDeviceCollector;
const Platform = @import("platform.zig").Platform;
const logger = @import("logger.zig");

// Platform-specific monitors
const mac_monitor = if (@import("builtin").target.os.tag == .macos) @import("monitor/mac_monitor.zig") else struct {
    pub const MacUsbMonitor = struct {
        allocator: std.mem.Allocator,
        monitor_ref: ?*UsbDeviceMonitor,
        is_running: bool,

        pub fn init(allocator: std.mem.Allocator, monitor_ref: *UsbDeviceMonitor) @This() {
            return .{
                .allocator = allocator,
                .monitor_ref = monitor_ref,
                .is_running = false,
            };
        }
        pub fn deinit(_: *@This()) void {}
        pub fn start(_: *@This()) !void {}
        pub fn stop(_: *@This()) void {}
    };
};

const windows_monitor = if (@import("builtin").target.os.tag == .windows) @import("monitor/windows_monitor.zig") else struct {
    pub const WindowsUsbMonitor = struct {
        allocator: std.mem.Allocator,
        monitor_ref: ?*UsbDeviceMonitor,
        is_running: bool,

        pub fn init(allocator: std.mem.Allocator, monitor_ref: *UsbDeviceMonitor) @This() {
            return .{
                .allocator = allocator,
                .monitor_ref = monitor_ref,
                .is_running = false,
            };
        }
        pub fn deinit(_: *@This()) void {}
        pub fn start(_: *@This()) !void {}
        pub fn stop(_: *@This()) void {}
    };
};

const linux_monitor = if (@import("builtin").target.os.tag == .linux) @import("monitor/linux_monitor.zig") else struct {
    pub const LinuxUsbMonitor = struct {
        allocator: std.mem.Allocator,
        monitor_ref: ?*UsbDeviceMonitor,
        is_running: bool,

        pub fn init(allocator: std.mem.Allocator, monitor_ref: *UsbDeviceMonitor) @This() {
            return .{
                .allocator = allocator,
                .monitor_ref = monitor_ref,
                .is_running = false,
            };
        }
        pub fn deinit(_: *@This()) void {}
        pub fn start(_: *@This()) !void {}
        pub fn stop(_: *@This()) void {}
    };
};

/// Device event types
pub const DeviceEvent = enum {
    connected,
    disconnected,
    err,
};

/// USB Device Event structure
pub const UsbDeviceEvent = struct {
    event_type: DeviceEvent,
    device: ?UsbDevice,
    timestamp: i64,

    pub fn init(event_type: DeviceEvent, device: ?UsbDevice) UsbDeviceEvent {
        return UsbDeviceEvent{
            .event_type = event_type,
            .device = device,
            .timestamp = std.time.timestamp(),
        };
    }
};

/// USB Device Monitor for real-time device change detection
pub const UsbDeviceMonitor = struct {
    allocator: std.mem.Allocator,
    platform: Platform,
    is_running: bool,
    should_stop: bool,
    collector: UsbDeviceCollector,
    
    // Store the callback function
    event_callback: ?DeviceEventCallback,
    
    // Platform-specific monitor instances
    mac_monitor_instance: ?mac_monitor.MacUsbMonitor,
    windows_monitor_instance: ?windows_monitor.WindowsUsbMonitor,
    linux_monitor_instance: ?linux_monitor.LinuxUsbMonitor,

    // Callback function type for device events
    pub const DeviceEventCallback = *const fn (monitor: *UsbDeviceMonitor, event: DeviceEvent, device: ?UsbDevice) void;

    const Self = @This();

    /// Initialize a new USB device monitor
    pub fn init(allocator: std.mem.Allocator) Self {
        const platform = Platform.current();
        var self = Self{
            .allocator = allocator,
            .platform = platform,
            .is_running = false,
            .should_stop = false,
            .collector = UsbDeviceCollector.init(allocator),
            .event_callback = null,
            .mac_monitor_instance = null,
            .windows_monitor_instance = null,
            .linux_monitor_instance = null,
        };

        // Initialize platform-specific monitor after self is created
        if (platform == .mac and @import("builtin").target.os.tag == .macos) {
            self.mac_monitor_instance = mac_monitor.MacUsbMonitor.init(allocator, &self);
        } else if (platform == .windows and @import("builtin").target.os.tag == .windows) {
            self.windows_monitor_instance = windows_monitor.WindowsUsbMonitor.init(allocator, &self);
        } else if (platform == .linux and @import("builtin").target.os.tag == .linux) {
            self.linux_monitor_instance = linux_monitor.LinuxUsbMonitor.init(allocator, &self);
        }

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.stop();
        if (self.mac_monitor_instance) |*monitor| {
            monitor.deinit();
        }
        if (self.windows_monitor_instance) |*monitor| {
            monitor.deinit();
        }
        if (self.linux_monitor_instance) |*monitor| {
            monitor.deinit();
        }
    }

    /// Start monitoring USB device changes
    pub fn start(self: *Self, callback: DeviceEventCallback) !void {
        if (self.is_running) {
            return error.AlreadyRunning;
        }

        if (!self.platform.isSupported()) {
            return error.PlatformNotSupported;
        }

        self.is_running = true;
        self.should_stop = false;
        self.event_callback = callback;

        switch (self.platform) {
            .mac => {
                if (self.mac_monitor_instance) |*monitor| {
                    // Set the monitor reference for the mac monitor
                    monitor.monitor_ref = self;
                    try monitor.start();

                    // Run the monitoring loop
                    try self.runMacMonitorLoop(callback);
                } else {
                    return error.MonitorNotInitialized;
                }
            },
            .windows => {
                if (self.windows_monitor_instance) |*monitor| {
                    // Set the monitor reference for the windows monitor
                    monitor.monitor_ref = self;
                    try monitor.start();

                    // Run the monitoring loop
                    try self.runWindowsMonitorLoop(callback);
                } else {
                    return error.MonitorNotInitialized;
                }
            },
            .linux => {
                if (self.linux_monitor_instance) |*monitor| {
                    // Set the monitor reference for the linux monitor
                    monitor.monitor_ref = self;
                    try monitor.start();

                    // Run the monitoring loop
                    try self.runLinuxMonitorLoop(callback);
                } else {
                    return error.MonitorNotInitialized;
                }
            },
            .unknown => return error.PlatformNotSupported,
        }
    }

    /// Stop monitoring
    pub fn stop(self: *Self) void {
        if (!self.is_running) return;

        self.should_stop = true;
        self.is_running = false;

        switch (self.platform) {
            .mac => {
                if (self.mac_monitor_instance) |*monitor| {
                    monitor.stop();
                }
            },
            .windows => {
                if (self.windows_monitor_instance) |*monitor| {
                    monitor.stop();
                }
            },
            .linux => {
                if (self.linux_monitor_instance) |*monitor| {
                    monitor.stop();
                }
            },
            else => {},
        }
    }

    /// Check if monitoring is currently active
    pub fn isRunning(self: *const Self) bool {
        return self.is_running;
    }

    /// Get the current platform
    pub fn getPlatform(self: *const Self) Platform {
        return self.platform;
    }

    /// Trigger a device event (called by platform-specific monitors)
    pub fn triggerEvent(self: *Self, event: UsbDeviceEvent) void {
        // Log the event for debugging
        switch (event.event_type) {
            .connected => {
                if (event.device) |device| {
                    logger.debug("Device connected: {?s} (VID: {s}, PID: {s})", .{ device.product_name, device.vendor_id, device.product_id });
                } else {
                    logger.debug("Device connected: Unknown device", .{});
                }
            },
            .disconnected => {
                if (event.device) |device| {
                    logger.debug("Device disconnected: {?s} (VID: {s}, PID: {s})", .{ device.product_name, device.vendor_id, device.product_id });
                } else {
                    logger.debug("Device disconnected: Unknown device", .{});
                }
            },
            .err => {
                logger.err("USB device error occurred", .{});
            },
        }
        
        // Call the user-provided callback if available
        if (self.event_callback) |callback| {
            callback(self, event.event_type, event.device);
        }
    }

    /// Run macOS-specific monitoring loop
    fn runMacMonitorLoop(self: *Self, _: DeviceEventCallback) !void {
        // The actual monitoring is handled by IOKit notifications in mac_monitor.zig
        // We need to run the Core Foundation run loop for IOKit notifications to work
        const c = @cImport({
            @cInclude("CoreFoundation/CoreFoundation.h");
        });
        
        logger.debug("Starting Core Foundation run loop for IOKit notifications...", .{});
        
        while (self.is_running and !self.should_stop) {
            // Run the run loop for a short time to process IOKit notifications
            const result = c.CFRunLoopRunInMode(c.kCFRunLoopDefaultMode, 0.1, 1); // Run for 0.1 seconds
            
            switch (result) {
                c.kCFRunLoopRunFinished => {
                    logger.debug("Run loop finished", .{});
                    break;
                },
                c.kCFRunLoopRunStopped => {
                    logger.debug("Run loop stopped", .{});
                    break;
                },
                c.kCFRunLoopRunTimedOut => {
                    // Normal timeout, continue
                },
                c.kCFRunLoopRunHandledSource => {
                    logger.debug("Run loop handled source", .{});
                },
                else => {
                    logger.debug("Run loop returned: {}", .{result});
                },
            }
        }
        
        logger.debug("Exiting Core Foundation run loop", .{});
    }

    /// Run Windows-specific monitoring loop
    fn runWindowsMonitorLoop(self: *Self, _: DeviceEventCallback) !void {
        // The actual monitoring is handled by WMI events in windows_monitor.zig
        // This function just keeps the daemon alive
        while (self.is_running and !self.should_stop) {
            std.Thread.sleep(100 * std.time.ns_per_ms); // Sleep for 100ms
        }
    }

    /// Run Linux-specific monitoring loop
    fn runLinuxMonitorLoop(self: *Self, _: DeviceEventCallback) !void {
        // The actual monitoring is handled by udev events in linux_monitor.zig
        // This function just keeps the daemon alive
        while (self.is_running and !self.should_stop) {
            std.Thread.sleep(100 * std.time.ns_per_ms); // Sleep for 100ms
        }
    }

    /// Run polling-based monitoring loop for Linux and Windows
    fn runPollingLoop(self: *Self, callback: DeviceEventCallback) !void {
        // Simplified polling implementation for compatibility
        while (self.is_running and !self.should_stop) {
            std.Thread.sleep(1000 * std.time.ns_per_ms); // Poll every second

            // Get current device list
            if (self.collector.listUsbDevices()) |current_devices| {
                defer {
                    for (current_devices) |*device| {
                        device.deinit(self.allocator);
                    }
                    self.allocator.free(current_devices);
                }

                // For now, just call the callback for each current device as "connected"
                for (current_devices) |device| {
                    callback(.connected, device);
                }
            } else |err| {
                logger.err("Failed to collect USB devices: {}", .{err});
                callback(.err, null);
            }
        }
    }

    /// Compare two USB devices for equality
    fn devicesEqual(self: *const Self, device1: UsbDevice, device2: UsbDevice) bool {
        _ = self;
        return std.mem.eql(u8, device1.vendor_id, device2.vendor_id) and
            std.mem.eql(u8, device1.product_id, device2.product_id) and
            std.mem.eql(u8, device1.name, device2.name);
    }

    /// Handle device events (called by platform-specific monitors)
    pub fn handleDeviceEvent(self: *Self, event: DeviceEvent, device: ?UsbDevice) void {
        // Log the event for debugging
        switch (event) {
            .connected => {
                if (device) |dev| {
                    logger.debug("USB device connected: {s}", .{dev.name});
                }
            },
            .disconnected => {
                if (device) |dev| {
                    logger.debug("USB device disconnected: {s}", .{dev.name});
                }
            },
            .err => {
                logger.err("USB monitoring error occurred", .{});
            },
        }
        
        // Call the user-provided callback if available
        if (self.event_callback) |callback| {
            callback(self, event, device);
        }
    }
};

/// Signal handler for graceful shutdown
var global_monitor: ?*UsbDeviceMonitor = null;

pub fn setupSignalHandler(_: *UsbDeviceMonitor) !void {
    // Note: Signal handling is simplified for cross-platform compatibility
    // In a production environment, you would implement proper signal handling
    // For now, we rely on the monitoring loop checking should_stop flag
}
