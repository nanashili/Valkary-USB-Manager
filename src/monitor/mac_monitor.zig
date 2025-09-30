const std = @import("std");
const UsbDevice = @import("../usb_device.zig").UsbDevice;
const daemon = @import("../daemon.zig");
const mac_parser = @import("../parser/mac_parser.zig");
const logger = @import("../logger.zig");

// IOKit C bindings for USB device monitoring
const c = @cImport({
    @cInclude("IOKit/IOKitLib.h");
    @cInclude("IOKit/usb/IOUSBLib.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

/// macOS-specific USB device monitor using IOKit notifications
pub const MacUsbMonitor = struct {
    allocator: std.mem.Allocator,
    notification_port: ?c.IONotificationPortRef,
    run_loop_source: ?c.CFRunLoopSourceRef,
    added_iterator: c.io_iterator_t,
    removed_iterator: c.io_iterator_t,
    monitor_ref: ?*daemon.UsbDeviceMonitor,
    is_running: bool,

    // Debouncing fields
    last_connect_time: i64,
    last_disconnect_time: i64,
    debounce_delay_ms: i64,
    device_state_stable: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, monitor_ref: *daemon.UsbDeviceMonitor) Self {
        return Self{
            .allocator = allocator,
            .notification_port = null,
            .run_loop_source = null,
            .added_iterator = 0,
            .removed_iterator = 0,
            .monitor_ref = monitor_ref,
            .is_running = false,
            .last_connect_time = 0,
            .last_disconnect_time = 0,
            .debounce_delay_ms = 0,
            .device_state_stable = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
    }

    pub fn start(self: *Self) !void {
        if (self.is_running) {
            return error.AlreadyRunning;
        }

        logger.debug("MacUsbMonitor: Starting IOKit monitoring...", .{});

        // Create notification port
        self.notification_port = c.IONotificationPortCreate(c.kIOMasterPortDefault);
        if (self.notification_port == null) {
            logger.err("MacUsbMonitor: Failed to create notification port", .{});
            return error.FailedToCreateNotificationPort;
        }
        logger.debug("MacUsbMonitor: Created notification port", .{});

        // Get run loop source
        self.run_loop_source = c.IONotificationPortGetRunLoopSource(self.notification_port.?);
        if (self.run_loop_source == null) {
            logger.err("MacUsbMonitor: Failed to get run loop source", .{});
            self.cleanup();
            return error.FailedToGetRunLoopSource;
        }
        logger.debug("MacUsbMonitor: Got run loop source", .{});

        // Add run loop source to current run loop
        c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), self.run_loop_source.?, c.kCFRunLoopDefaultMode);
        logger.debug("MacUsbMonitor: Added run loop source to current run loop", .{});

        // Create matching dictionary for USB devices
        const matching_dict = c.IOServiceMatching("IOUSBDevice");
        if (matching_dict == null) {
            self.cleanup();
            return error.FailedToCreateMatchingDictionary;
        }

        // Register for device addition notifications
        logger.debug("MacUsbMonitor: Registering for device addition notifications...", .{});
        const add_result = c.IOServiceAddMatchingNotification(
            self.notification_port.?,
            c.kIOFirstMatchNotification,
            matching_dict,
            deviceAddedCallback,
            @ptrCast(self),
            &self.added_iterator,
        );

        if (add_result != c.KERN_SUCCESS) {
            logger.err("MacUsbMonitor: Failed to register for device addition notifications: {}", .{add_result});
            self.cleanup();
            return error.FailedToRegisterAddedNotification;
        }
        logger.debug("MacUsbMonitor: Successfully registered for device addition notifications", .{});

        // Create another matching dictionary for removal notifications
        const matching_dict_removed = c.IOServiceMatching("IOUSBDevice");
        if (matching_dict_removed == null) {
            self.cleanup();
            return error.FailedToCreateMatchingDictionary;
        }

        // Register for device removal notifications
        logger.debug("MacUsbMonitor: Registering for device removal notifications...", .{});
        const remove_result = c.IOServiceAddMatchingNotification(
            self.notification_port.?,
            c.kIOTerminatedNotification,
            matching_dict_removed,
            deviceRemovedCallback,
            @ptrCast(self),
            &self.removed_iterator,
        );

        if (remove_result != c.KERN_SUCCESS) {
            logger.err("MacUsbMonitor: Failed to register for device removal notifications: {}", .{remove_result});
            self.cleanup();
            return error.FailedToRegisterRemovedNotification;
        }
        logger.debug("MacUsbMonitor: Successfully registered for device removal notifications", .{});

        // Process existing devices to arm the notification
        logger.debug("MacUsbMonitor: Processing existing devices to arm notifications...", .{});
        self.processExistingDevices();

        self.is_running = true;
        logger.debug("MacUsbMonitor: IOKit monitoring started successfully", .{});
    }

    pub fn stop(self: *Self) void {
        if (!self.is_running) {
            return;
        }

        self.cleanup();
        self.is_running = false;
    }

    fn cleanup(self: *Self) void {
        // Remove run loop source
        if (self.run_loop_source) |source| {
            c.CFRunLoopRemoveSource(c.CFRunLoopGetCurrent(), source, c.kCFRunLoopDefaultMode);
            self.run_loop_source = null;
        }

        // Release iterators
        if (self.added_iterator != 0) {
            _ = c.IOObjectRelease(self.added_iterator);
            self.added_iterator = 0;
        }

        if (self.removed_iterator != 0) {
            _ = c.IOObjectRelease(self.removed_iterator);
            self.removed_iterator = 0;
        }

        // Destroy notification port
        if (self.notification_port) |port| {
            c.IONotificationPortDestroy(port);
            self.notification_port = null;
        }
    }

    fn processExistingDevices(self: *Self) void {
        // Process any existing devices to arm the notification
        var service: c.io_service_t = c.IOIteratorNext(self.added_iterator);
        while (service != 0) {
            _ = c.IOObjectRelease(service);
            service = c.IOIteratorNext(self.added_iterator);
        }

        service = c.IOIteratorNext(self.removed_iterator);
        while (service != 0) {
            _ = c.IOObjectRelease(service);
            service = c.IOIteratorNext(self.removed_iterator);
        }
    }

    fn shouldDebounceConnectEvent(self: *Self) bool {
        const current_time = std.time.milliTimestamp();
        const time_since_last_connect = current_time - self.last_connect_time;
        const time_since_last_disconnect = current_time - self.last_disconnect_time;

        // If we just had a disconnect event recently, wait longer before allowing connect
        if (time_since_last_disconnect < self.debounce_delay_ms) {
            logger.debug("MacUsbMonitor: Debouncing connect event ({}ms since disconnect)", .{time_since_last_disconnect});
            return true;
        }

        // If we had a recent connect event, debounce
        if (time_since_last_connect < self.debounce_delay_ms) {
            logger.debug("MacUsbMonitor: Debouncing connect event ({}ms since last connect)", .{time_since_last_connect});
            return true;
        }

        self.last_connect_time = current_time;
        self.device_state_stable = false; // Mark as unstable during transition
        return false;
    }

    fn shouldDebounceDisconnectEvent(self: *Self) bool {
        const current_time = std.time.milliTimestamp();
        const time_since_last_disconnect = current_time - self.last_disconnect_time;
        const time_since_last_connect = current_time - self.last_connect_time;

        // If we just had a connect event recently, wait longer before allowing disconnect
        if (time_since_last_connect < self.debounce_delay_ms) {
            logger.debug("MacUsbMonitor: Debouncing disconnect event ({}ms since connect)", .{time_since_last_connect});
            return true;
        }

        // If we had a recent disconnect event, debounce
        if (time_since_last_disconnect < self.debounce_delay_ms) {
            logger.debug("MacUsbMonitor: Debouncing disconnect event ({}ms since last disconnect)", .{time_since_last_disconnect});
            return true;
        }

        self.last_disconnect_time = current_time;
        self.device_state_stable = false; // Mark as unstable during transition
        return false;
    }

    fn deviceAddedCallback(refcon: ?*anyopaque, iterator: c.io_iterator_t) callconv(.c) void {
        logger.debug("MacUsbMonitor: deviceAddedCallback called", .{});
        if (refcon == null) {
            logger.err("MacUsbMonitor: deviceAddedCallback called with null refcon", .{});
            return;
        }

        const self: *MacUsbMonitor = @ptrCast(@alignCast(refcon));
        self.handleDeviceAdded(iterator);
    }

    fn deviceRemovedCallback(refcon: ?*anyopaque, iterator: c.io_iterator_t) callconv(.c) void {
        logger.debug("MacUsbMonitor: deviceRemovedCallback called", .{});
        if (refcon == null) {
            logger.err("MacUsbMonitor: deviceRemovedCallback called with null refcon", .{});
            return;
        }

        const self: *MacUsbMonitor = @ptrCast(@alignCast(refcon));
        self.handleDeviceRemoved(iterator);
    }

    fn handleDeviceAdded(self: *Self, iterator: c.io_iterator_t) void {
        logger.debug("MacUsbMonitor: handleDeviceAdded called", .{});

        // Check if we should debounce this connect event
        if (self.shouldDebounceConnectEvent()) {
            // Still need to consume the iterator to prevent memory leaks
            var service: c.io_service_t = c.IOIteratorNext(iterator);
            while (service != 0) {
                _ = c.IOObjectRelease(service);
                service = c.IOIteratorNext(iterator);
            }
            return;
        }

        var service: c.io_service_t = c.IOIteratorNext(iterator);
        while (service != 0) {
            defer _ = c.IOObjectRelease(service);

            logger.debug("MacUsbMonitor: Processing added device service", .{});
            // Get device information and create UsbDevice
            if (self.createUsbDeviceFromService(service)) |device| {
                logger.debug("MacUsbMonitor: Created device: {s}", .{device.name});
                const event = daemon.UsbDeviceEvent.init(.connected, device);
                if (self.monitor_ref) |monitor| {
                    logger.debug("MacUsbMonitor: Triggering connected event", .{});
                    monitor.triggerEvent(event);
                } else {
                    logger.err("MacUsbMonitor: No monitor reference available", .{});
                }
            } else |err| {
                logger.err("MacUsbMonitor: Failed to create device from service: {}", .{err});
            }

            service = c.IOIteratorNext(iterator);
        }
    }

    fn handleDeviceRemoved(self: *Self, iterator: c.io_iterator_t) void {
        logger.debug("MacUsbMonitor: handleDeviceRemoved called", .{});

        // Check if we should debounce this disconnect event
        if (self.shouldDebounceDisconnectEvent()) {
            // Still need to consume the iterator to prevent memory leaks
            var service: c.io_service_t = c.IOIteratorNext(iterator);
            while (service != 0) {
                _ = c.IOObjectRelease(service);
                service = c.IOIteratorNext(iterator);
            }
            return;
        }

        var service: c.io_service_t = c.IOIteratorNext(iterator);
        while (service != 0) {
            defer _ = c.IOObjectRelease(service);

            logger.debug("MacUsbMonitor: Processing removed device service", .{});
            // Get device information and create UsbDevice
            if (self.createUsbDeviceFromService(service)) |device| {
                logger.debug("MacUsbMonitor: Created device for removal: {s}", .{device.name});
                const event = daemon.UsbDeviceEvent.init(.disconnected, device);
                if (self.monitor_ref) |monitor| {
                    logger.debug("MacUsbMonitor: Triggering disconnected event", .{});
                    monitor.triggerEvent(event);
                } else {
                    logger.err("MacUsbMonitor: No monitor reference available", .{});
                }
            } else |err| {
                logger.err("MacUsbMonitor: Failed to create device from service: {}", .{err});
            }

            service = c.IOIteratorNext(iterator);
        }
    }

    fn createUsbDeviceFromService(self: *Self, service: c.io_service_t) !UsbDevice {
        // Extract real device properties from IOService
        var properties: c.CFMutableDictionaryRef = undefined;
        const result = c.IORegistryEntryCreateCFProperties(service, &properties, c.kCFAllocatorDefault, 0);

        if (result != c.KERN_SUCCESS) {
            // Fallback to basic device info if properties can't be read
            const name = try self.allocator.dupe(u8, "Unknown USB Device");
            const vendor_id = try self.allocator.dupe(u8, "0000");
            const product_id = try self.allocator.dupe(u8, "0000");

            return UsbDevice.init(name, vendor_id, product_id, null, null, null);
        }

        defer c.CFRelease(properties);

        // Extract device name (try multiple possible keys)
        var device_name: []const u8 = "Unknown USB Device";
        if (self.getCFStringProperty(properties, "USB Product Name")) |name| {
            device_name = name;
        } else if (self.getCFStringProperty(properties, "kUSBProductString")) |name| {
            device_name = name;
        } else if (self.getCFStringProperty(properties, "IORegistryEntryName")) |name| {
            device_name = name;
        }

        // Extract vendor ID
        var vendor_id_str: []const u8 = "0000";
        if (self.getCFNumberProperty(properties, "idVendor")) |vendor_id| {
            vendor_id_str = try std.fmt.allocPrint(self.allocator, "0x{x:0>4}", .{vendor_id});
        }

        // Extract product ID
        var product_id_str: []const u8 = "0000";
        if (self.getCFNumberProperty(properties, "idProduct")) |product_id| {
            product_id_str = try std.fmt.allocPrint(self.allocator, "0x{x:0>4}", .{product_id});
        }

        // Extract product name (optional)
        const product_name = self.getCFStringProperty(properties, "USB Product Name") orelse
            self.getCFStringProperty(properties, "kUSBProductString");

        // Extract serial number (optional)
        const serial_number = self.getCFStringProperty(properties, "USB Serial Number") orelse
            self.getCFStringProperty(properties, "kUSBSerialNumberString");

        const name_copy = try self.allocator.dupe(u8, device_name);
        const product_name_copy = if (product_name) |pn| try self.allocator.dupe(u8, pn) else null;
        const serial_copy = if (serial_number) |sn| try self.allocator.dupe(u8, sn) else null;

        return UsbDevice.init(
            name_copy,
            vendor_id_str,
            product_id_str,
            product_name_copy,
            serial_copy,
            null, // device_id
        );
    }

    fn getCFStringProperty(self: *Self, properties: c.CFDictionaryRef, key: []const u8) ?[]const u8 {
        const cf_key = c.CFStringCreateWithCString(c.kCFAllocatorDefault, key.ptr, c.kCFStringEncodingUTF8);
        defer c.CFRelease(cf_key);

        const cf_value = c.CFDictionaryGetValue(properties, cf_key);
        if (cf_value == null) return null;

        if (c.CFGetTypeID(cf_value) != c.CFStringGetTypeID()) return null;

        const cf_string: c.CFStringRef = @ptrCast(cf_value);
        const length = c.CFStringGetLength(cf_string);
        const max_size = c.CFStringGetMaximumSizeForEncoding(length, c.kCFStringEncodingUTF8) + 1;

        // Allocate buffer with proper memory management
        const buffer = self.allocator.alloc(u8, @intCast(max_size)) catch return null;
        defer self.allocator.free(buffer);

        if (c.CFStringGetCString(cf_string, buffer.ptr, @intCast(buffer.len), c.kCFStringEncodingUTF8) != 0) {
            const str_len = std.mem.len(@as([*:0]const u8, @ptrCast(buffer.ptr)));
            // Return a copy that the caller owns
            return self.allocator.dupe(u8, buffer[0..str_len]) catch null;
        }

        return null;
    }

    fn getCFNumberProperty(self: *Self, properties: c.CFDictionaryRef, key: []const u8) ?u32 {
        _ = self;
        const cf_key = c.CFStringCreateWithCString(c.kCFAllocatorDefault, key.ptr, c.kCFStringEncodingUTF8);
        defer c.CFRelease(cf_key);

        const cf_value = c.CFDictionaryGetValue(properties, cf_key);
        if (cf_value == null) return null;

        if (c.CFGetTypeID(cf_value) != c.CFNumberGetTypeID()) return null;

        const cf_number: c.CFNumberRef = @ptrCast(cf_value);
        var value: u32 = 0;

        if (c.CFNumberGetValue(cf_number, c.kCFNumberSInt32Type, &value) != 0) {
            return value;
        }

        return null;
    }
};
