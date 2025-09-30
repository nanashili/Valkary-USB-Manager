const std = @import("std");
pub const UsbDevice = @import("usb_device.zig").UsbDevice;
const UsbDeviceCollector = @import("collector.zig").UsbDeviceCollector;
const Platform = @import("platform.zig").Platform;

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
    
    // Platform-specific monitor instances
    mac_monitor_instance: ?mac_monitor.MacUsbMonitor,
    windows_monitor_instance: ?windows_monitor.WindowsUsbMonitor,
    linux_monitor_instance: ?linux_monitor.LinuxUsbMonitor,
    
    // Callback function type for device events
    pub const DeviceEventCallback = *const fn (event: DeviceEvent, device: ?UsbDevice) void;
    
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
        _ = self;
        switch (event.event_type) {
            .connected => {
                if (event.device) |device| {
                    std.log.debug("Device connected: {?s} (VID: {s}, PID: {s})", .{ device.product_name, device.vendor_id, device.product_id });
                } else {
                    std.log.debug("Device connected: Unknown device", .{});
                }
            },
            .disconnected => {
                if (event.device) |device| {
                    std.log.debug("Device disconnected: {?s} (VID: {s}, PID: {s})", .{ device.product_name, device.vendor_id, device.product_id });
                } else {
                    std.log.debug("Device disconnected: Unknown device", .{});
                }
            },
            .err => {
                std.log.err("USB device error occurred", .{});
            },
        }
    }

    /// Run macOS-specific monitoring loop
    fn runMacMonitorLoop(self: *Self, _: DeviceEventCallback) !void {
        // The actual monitoring is handled by IOKit notifications in mac_monitor.zig
        // This function just keeps the daemon alive
        while (self.is_running and !self.should_stop) {
            std.Thread.sleep(100 * std.time.ns_per_ms); // Sleep for 100ms
        }
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
                std.log.err("Failed to collect USB devices: {}", .{err});
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
        _ = self;
        switch (event) {
            .connected => {
                if (device) |dev| {
                    std.log.debug("USB device connected: {s}", .{dev.name});
                }
            },
            .disconnected => {
                if (device) |dev| {
                    std.log.debug("USB device disconnected: {s}", .{dev.name});
                }
            },
            .err => {
                std.log.err("USB monitoring error occurred", .{});
            },
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