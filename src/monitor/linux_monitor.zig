const std = @import("std");
const daemon = @import("../daemon.zig");
const UsbDevice = @import("../usb_device.zig").UsbDevice;
const builtin = @import("builtin");
const logger = @import("../logger.zig");

// Only compile Linux-specific code when targeting Linux
pub const LinuxUsbMonitor = if (builtin.target.os.tag == .linux) LinuxUsbMonitorImpl else LinuxUsbMonitorStub;

// Stub implementation for non-Linux platforms
const LinuxUsbMonitorStub = struct {
    allocator: std.mem.Allocator,
    monitor_ref: ?*daemon.UsbDeviceMonitor,
    is_running: bool,

    pub fn init(allocator: std.mem.Allocator, monitor_ref: *daemon.UsbDeviceMonitor) @This() {
        return .{
            .allocator = allocator,
            .monitor_ref = monitor_ref,
            .is_running = false,
        };
    }

    pub fn deinit(_: *@This()) void {}
    pub fn start(_: *@This()) !void {
        return error.UnsupportedPlatform;
    }
    pub fn stop(_: *@This()) void {}
};

// Real implementation for Linux
const LinuxUsbMonitorImpl = struct {
    // C bindings for udev
    const UdevContext = opaque {};
    const UdevMonitor = opaque {};
    const UdevDevice = opaque {};

    // Extern function declarations
    extern fn udev_new() ?*UdevContext;
    extern fn udev_unref(udev: *UdevContext) void;
    extern fn udev_monitor_new_from_netlink(udev: *UdevContext, name: [*:0]const u8) ?*UdevMonitor;
    extern fn udev_monitor_filter_add_match_subsystem_devtype(udev_monitor: *UdevMonitor, subsystem: [*:0]const u8, devtype: ?[*:0]const u8) c_int;
    extern fn udev_monitor_enable_receiving(udev_monitor: *UdevMonitor) c_int;
    extern fn udev_monitor_get_fd(udev_monitor: *UdevMonitor) c_int;
    extern fn udev_monitor_receive_device(udev_monitor: *UdevMonitor) ?*UdevDevice;
    extern fn udev_monitor_unref(udev_monitor: *UdevMonitor) void;
    extern fn udev_device_get_action(udev_device: *UdevDevice) ?[*:0]const u8;
    extern fn udev_device_get_devnode(udev_device: *UdevDevice) ?[*:0]const u8;
    extern fn udev_device_get_property_value(udev_device: *UdevDevice, key: [*:0]const u8) ?[*:0]const u8;
    extern fn udev_device_get_sysattr_value(udev_device: *UdevDevice, sysattr: [*:0]const u8) ?[*:0]const u8;
    extern fn udev_device_unref(udev_device: *UdevDevice) void;
    // Custom pollfd definition to avoid cross-compilation issues
    const pollfd = extern struct {
        fd: c_int,
        events: c_short,
        revents: c_short,
    };
    
    const POLL_IN: c_short = 1;
    
    extern fn poll(fds: [*]pollfd, nfds: c_ulong, timeout: c_int) c_int;

    allocator: std.mem.Allocator,
    monitor_ref: ?*daemon.UsbDeviceMonitor,
    is_running: bool,
    should_stop: bool,
    udev_context: ?*UdevContext,
    udev_monitor: ?*UdevMonitor,
    monitor_thread: ?std.Thread,
    monitor_fd: c_int,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, monitor_ref: *daemon.UsbDeviceMonitor) Self {
        return Self{
            .allocator = allocator,
            .monitor_ref = monitor_ref,
            .is_running = false,
            .should_stop = false,
            .udev_context = null,
            .udev_monitor = null,
            .monitor_thread = null,
            .monitor_fd = -1,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        
        if (self.udev_monitor) |monitor| {
            udev_monitor_unref(monitor);
            self.udev_monitor = null;
        }
        
        if (self.udev_context) |context| {
            udev_unref(context);
            self.udev_context = null;
        }
    }

    pub fn start(self: *Self) !void {
        if (self.is_running) {
            return error.AlreadyRunning;
        }

        // Initialize udev
        self.udev_context = udev_new() orelse {
            return error.UdevInitializationFailed;
        };

        // Create udev monitor for kernel events
        self.udev_monitor = udev_monitor_new_from_netlink(self.udev_context.?, "kernel") orelse {
            return error.UdevMonitorCreationFailed;
        };

        // Filter for USB subsystem events
        if (udev_monitor_filter_add_match_subsystem_devtype(self.udev_monitor.?, "usb", "usb_device") < 0) {
            return error.UdevFilterSetupFailed;
        }

        // Enable receiving events
        if (udev_monitor_enable_receiving(self.udev_monitor.?) < 0) {
            return error.UdevMonitorEnableFailed;
        }

        // Get file descriptor for polling
        self.monitor_fd = udev_monitor_get_fd(self.udev_monitor.?);
        if (self.monitor_fd < 0) {
            return error.UdevFileDescriptorFailed;
        }

        self.is_running = true;
        self.should_stop = false;

        // Start monitoring thread
        self.monitor_thread = try std.Thread.spawn(.{}, monitoringThread, .{self});
        
        logger.info("Linux real-time USB monitoring started (udev-based)", .{});
    }

    pub fn stop(self: *Self) void {
        if (!self.is_running) return;

        self.should_stop = true;
        self.is_running = false;

        if (self.monitor_thread) |thread| {
            thread.join();
            self.monitor_thread = null;
        }
        
        logger.info("Linux USB monitoring stopped", .{});
    }

    fn monitoringThread(self: *Self) void {
        self.runUdevMonitoring() catch |err| {
            logger.err("Linux USB monitoring failed: {}", .{err});
        };
    }

    fn runUdevMonitoring(self: *Self) !void {
        var poll_fd = pollfd{
            .fd = self.monitor_fd,
            .events = POLL_IN,
            .revents = 0,
        };

        while (self.is_running and !self.should_stop) {
            // Poll for events with 1 second timeout
            const poll_result = poll(@ptrCast(&poll_fd), 1, 1000);
            
            if (poll_result < 0) {
                logger.err("udev poll failed", .{});
                break;
            }
            
            if (poll_result == 0) {
                // Timeout, continue polling
                continue;
            }

            if (poll_fd.revents & POLL_IN != 0) {
                // Event available, process it
                try self.processUdevEvent();
            }
        }
    }

    fn processUdevEvent(self: *Self) !void {
        const device = udev_monitor_receive_device(self.udev_monitor.?) orelse {
            return; // No device event
        };
        defer udev_device_unref(device);

        const action_ptr = udev_device_get_action(device);
        if (action_ptr == null) return;

        const action = std.mem.span(action_ptr.?);
        
        if (std.mem.eql(u8, action, "add")) {
            // Device connected
            if (self.createUsbDeviceFromUdev(device)) |usb_device| {
                if (self.monitor_ref) |monitor| {
                    monitor.handleDeviceEvent(.connected, usb_device);
                }
            } else |err| {
                logger.debug("Failed to create USB device from udev: {}", .{err});
            }
        } else if (std.mem.eql(u8, action, "remove")) {
            // Device disconnected
            if (self.createUsbDeviceFromUdev(device)) |usb_device| {
                if (self.monitor_ref) |monitor| {
                    monitor.handleDeviceEvent(.disconnected, usb_device);
                }
            } else |err| {
                    logger.debug("Failed to create USB device from udev: {}", .{err});
                }
        }
    }

    fn createUsbDeviceFromUdev(self: *Self, device: *UdevDevice) !UsbDevice {
        // Extract device information from udev
        const devnode_ptr = udev_device_get_devnode(device);
        const vendor_id_ptr = udev_device_get_sysattr_value(device, "idVendor");
        const product_id_ptr = udev_device_get_sysattr_value(device, "idProduct");
        const product_ptr = udev_device_get_sysattr_value(device, "product");
        const serial_ptr = udev_device_get_sysattr_value(device, "serial");

        // Create device name from devnode or use a default
        const device_name = if (devnode_ptr) |ptr| 
            try self.allocator.dupe(u8, std.mem.span(ptr))
        else 
            try self.allocator.dupe(u8, "Unknown USB Device");

        // Extract vendor ID
        const vendor_id = if (vendor_id_ptr) |ptr|
            try self.allocator.dupe(u8, std.mem.span(ptr))
        else
            try self.allocator.dupe(u8, "0000");

        // Extract product ID
        const product_id = if (product_id_ptr) |ptr|
            try self.allocator.dupe(u8, std.mem.span(ptr))
        else
            try self.allocator.dupe(u8, "0000");

        // Extract product name
        const product_name = if (product_ptr) |ptr|
            try self.allocator.dupe(u8, std.mem.span(ptr))
        else
            null;

        // Extract serial number
        const serial_number = if (serial_ptr) |ptr|
            try self.allocator.dupe(u8, std.mem.span(ptr))
        else
            null;

        // Use devnode as device_id if available
        const device_id = if (devnode_ptr) |ptr| 
            try self.allocator.dupe(u8, std.mem.span(ptr)) 
        else 
            null;

        return UsbDevice{
            .name = device_name,
            .vendor_id = vendor_id,
            .product_id = product_id,
            .product_name = product_name,
            .serial_number = serial_number,
            .device_id = device_id,
        };
    }
};