const std = @import("std");
const UsbDevice = @import("../usb_device.zig").UsbDevice;

/// Device information structure for parsing lsusb output
const DeviceInfo = struct {
    name: ?[]const u8 = null,
    vendor_id: ?[]const u8 = null,
    product_id: ?[]const u8 = null,
    product_name: ?[]const u8 = null,
    serial_number: ?[]const u8 = null,
    device_id: ?[]const u8 = null,

    pub fn deinit(self: *DeviceInfo, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.vendor_id) |vendor_id| allocator.free(vendor_id);
        if (self.product_id) |product_id| allocator.free(product_id);
        if (self.product_name) |product_name| allocator.free(product_name);
        if (self.serial_number) |serial_number| allocator.free(serial_number);
        if (self.device_id) |device_id| allocator.free(device_id);
    }
};

/// Parser for Linux lsusb output
pub const LinuxParser = struct {
    pub fn parse(self: *LinuxParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice {
        _ = self;
        var devices = std.array_list.Managed(UsbDevice).init(allocator);
        errdefer {
            for (devices.items) |*device| {
                device.deinit(allocator);
            }
            devices.deinit();
        }

        var current_device: ?DeviceInfo = null;
        var lines = std.mem.splitScalar(u8, output, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            if (try parseDeviceHeader(allocator, trimmed)) |device_info| {
                if (current_device) |*cd| {
                    if (try createUsbDevice(allocator, cd)) |device| {
                        try devices.append(device);
                    }
                    cd.deinit(allocator);
                }
                current_device = device_info;
            } else if (current_device != null) {
                try parseDeviceProperty(allocator, &current_device.?, trimmed);
            }
        }

        if (current_device) |*cd| {
            if (try createUsbDevice(allocator, cd)) |device| {
                try devices.append(device);
            }
            cd.deinit(allocator);
        }

        return devices.toOwnedSlice();
    }

    fn parseDeviceHeader(allocator: std.mem.Allocator, line: []const u8) !?DeviceInfo {
        // Pattern: Bus 003 Device 037: ID 18d1:4ee7 Google Inc.
        if (!std.mem.startsWith(u8, line, "Bus ")) return null;

        const id_pos = std.mem.indexOf(u8, line, "ID ") orelse return null;
        const after_id = line[id_pos + 3 ..];

        // Parse vendor:product
        const colon_pos = std.mem.indexOfScalar(u8, after_id, ':') orelse return null;
        if (colon_pos != 4) return null; // vendor ID should be 4 chars

        const vendor_id = after_id[0..4];
        const after_colon = after_id[colon_pos + 1 ..];

        if (after_colon.len < 4) return null;
        const product_id = after_colon[0..4];

        // Find product name (everything after the space following product ID)
        const space_pos = std.mem.indexOfScalar(u8, after_colon[4..], ' ') orelse return null;
        const product_name = std.mem.trim(u8, after_colon[4 + space_pos ..], &std.ascii.whitespace);

        // Extract bus and device numbers for device_id
        const bus_start = 4; // after "Bus "
        const bus_end = std.mem.indexOfScalar(u8, line[bus_start..], ' ') orelse return null;
        const device_start = std.mem.indexOf(u8, line, "Device ") orelse return null;
        const device_end = std.mem.indexOfScalar(u8, line[device_start + 7..], ':') orelse return null;
        
        const bus_num = line[bus_start..bus_start + bus_end];
        const device_num = line[device_start + 7..device_start + 7 + device_end];

        var device_info = DeviceInfo{};
        device_info.name = try allocator.dupe(u8, product_name);
        device_info.vendor_id = try allocator.dupe(u8, vendor_id);
        device_info.product_id = try allocator.dupe(u8, product_id);
        device_info.device_id = try std.fmt.allocPrint(allocator, "{s}:{s}", .{bus_num, device_num});

        return device_info;
    }

    fn parseDeviceProperty(allocator: std.mem.Allocator, device_info: *DeviceInfo, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        
        // Only parse serial number from detailed output
        if (std.mem.indexOf(u8, trimmed, "iSerial")) |_| {
            if (extractSerial(allocator, trimmed)) |serial| {
                if (device_info.serial_number) |old_serial| {
                    allocator.free(old_serial);
                }
                device_info.serial_number = serial;
            } else |_| {}
        }
    }

    fn extractSerial(allocator: std.mem.Allocator, line: []const u8) !?[]const u8 {
        // Pattern: "  iSerial   3 HT85G1A03400"
        var parts = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);
        _ = parts.next(); // skip "iSerial"
        _ = parts.next(); // skip number
        if (parts.next()) |serial| {
            if (serial.len > 0) {
                return try allocator.dupe(u8, serial);
            }
        }
        return null;
    }

    fn createUsbDevice(allocator: std.mem.Allocator, device_info: *const DeviceInfo) !?UsbDevice {
        if (!hasRequiredFields(device_info)) return null;

        return UsbDevice.init(
            try allocator.dupe(u8, device_info.name.?),
            try allocator.dupe(u8, device_info.vendor_id.?),
            try allocator.dupe(u8, device_info.product_id.?),
            device_info.product_name,
            if (device_info.serial_number) |sn| try allocator.dupe(u8, sn) else null,
            if (device_info.device_id) |did| try allocator.dupe(u8, did) else null,
        );
    }

    fn hasRequiredFields(device_info: *const DeviceInfo) bool {
        return device_info.name != null and 
               device_info.vendor_id != null and 
               device_info.product_id != null;
    }
};
