const std = @import("std");
const UsbDevice = @import("../usb_device.zig").UsbDevice;

/// Parser for macOS ioreg output
pub const MacParser = struct {
    pub fn parse(self: *MacParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice {
        _ = self;

        
        var devices = std.array_list.Managed(UsbDevice).init(allocator);
        errdefer {
            for (devices.items) |*device| {
                device.deinit(allocator);
            }
            devices.deinit();
        }

        var lines = std.mem.splitScalar(u8, output, '\n');
        var current_device: ?DeviceInfo = null;
        var device_brace_level: i32 = -1;
        var brace_count: i32 = 0;
        var line_count: u32 = 0;

        while (lines.next()) |line| {
            line_count += 1;
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;

            // Count braces to track nesting level
            for (trimmed) |c| {
                if (c == '{') brace_count += 1;
                if (c == '}') brace_count -= 1;
            }

            // Check if this line contains USB device properties
            if (std.mem.indexOf(u8, trimmed, "\"USB Product Name\"") != null or
                std.mem.indexOf(u8, trimmed, "\"kUSBProductString\"") != null or
                std.mem.indexOf(u8, trimmed, "\"idVendor\"") != null or
                std.mem.indexOf(u8, trimmed, "\"idProduct\"") != null) {
                
                // If we don't have a current device or we're at a different brace level, start a new device
                if (current_device == null or device_brace_level != brace_count) {
                    // Save previous device if it has required fields, otherwise clean it up
                    if (current_device != null) {
                        if (hasRequiredFields(current_device.?)) {
                            if (try createUsbDevice(allocator, current_device.?)) |device| {
                                try devices.append(device);
                            }
                            current_device.?.deinit(allocator);
                        } else {
                            current_device.?.deinit(allocator);
                        }
                    }
                    current_device = DeviceInfo{};
                    device_brace_level = brace_count;
                }
            }

            if (current_device != null) {
                try parseDeviceProperty(allocator, trimmed, &current_device.?);

                // Check if we've reached the end of a device block (closing brace at the device level)
                if (brace_count < device_brace_level) {
                    if (hasRequiredFields(current_device.?)) {
                        if (try createUsbDevice(allocator, current_device.?)) |device| {
                            try devices.append(device);
                        }
                        current_device.?.deinit(allocator);
                    } else {
                        current_device.?.deinit(allocator);
                    }
                    current_device = null;
                    device_brace_level = -1;
                }
            }
        }

        // Handle the last device if it exists
        if (current_device != null) {
            if (hasRequiredFields(current_device.?)) {
                if (try createUsbDevice(allocator, current_device.?)) |device| {
                    try devices.append(device);
                }
                current_device.?.deinit(allocator);
            } else {
                current_device.?.deinit(allocator);
            }
        }
        return devices.toOwnedSlice();
    }

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

    fn parseDeviceProperty(allocator: std.mem.Allocator, line: []const u8, device: *DeviceInfo) !void {
        if (std.mem.indexOf(u8, line, "\"USB Product Name\" = ")) |_| {
            if (extractStringValue(line)) |name| {
                device.name = try allocator.dupe(u8, name);
            }
        } else if (std.mem.indexOf(u8, line, "\"USB Vendor Name\" = ")) |_| {
            if (extractStringValue(line)) |product_name| {
                device.product_name = try allocator.dupe(u8, product_name);
            }
        } else if (std.mem.indexOf(u8, line, "\"USB Serial Number\" = ")) |_| {
            if (extractStringValue(line)) |serial| {
                device.serial_number = try allocator.dupe(u8, serial);
            }
        } else if (std.mem.indexOf(u8, line, "\"idVendor\" = ")) |_| {
            if (extractNumberValue(line)) |vendor_id_num| {
                device.vendor_id = try std.fmt.allocPrint(allocator, "{x:0>4}", .{vendor_id_num});
            }
        } else if (std.mem.indexOf(u8, line, "\"idProduct\" = ")) |_| {
            if (extractNumberValue(line)) |product_id_num| {
                device.product_id = try std.fmt.allocPrint(allocator, "{x:0>4}", .{product_id_num});
            }
        } else if (std.mem.indexOf(u8, line, "\"locationID\" = ")) |_| {
            if (extractStringValue(line)) |device_id| {
                device.device_id = try allocator.dupe(u8, device_id);
            }
        }
    }

    fn extractStringValue(line: []const u8) ?[]const u8 {
        // Find the pattern "key" = "value"
        if (std.mem.indexOf(u8, line, " = \"")) |eq_pos| {
            const start = eq_pos + 4; // Skip ' = "'
            if (std.mem.lastIndexOfScalar(u8, line, '"')) |end_pos| {
                if (end_pos > start) {
                    return line[start..end_pos];
                }
            }
        }
        return null;
    }

    fn extractNumberValue(line: []const u8) ?u32 {
        // Find the pattern "key" = number
        if (std.mem.indexOf(u8, line, " = ")) |eq_pos| {
            const start = eq_pos + 3; // Skip ' = '
            const value_str = std.mem.trim(u8, line[start..], &std.ascii.whitespace);
            return std.fmt.parseInt(u32, value_str, 10) catch null;
        }
        return null;
    }

    fn hasRequiredFields(device_info: DeviceInfo) bool {
        return device_info.name != null and device_info.vendor_id != null and device_info.product_id != null;
    }

    fn createUsbDevice(allocator: std.mem.Allocator, device_info: DeviceInfo) !?UsbDevice {
        const name = device_info.name orelse return null;
        const vendor_id = device_info.vendor_id orelse return null;
        const product_id = device_info.product_id orelse return null;

        return UsbDevice.init(
            try allocator.dupe(u8, name),
            try allocator.dupe(u8, vendor_id),
            try allocator.dupe(u8, product_id),
            if (device_info.product_name) |pn| try allocator.dupe(u8, pn) else null,
            if (device_info.serial_number) |sn| try allocator.dupe(u8, sn) else null,
            if (device_info.device_id) |di| try allocator.dupe(u8, di) else null,
        );
    }

    fn isAllZeros(str: []const u8) bool {
        for (str) |c| {
            if (c != '0') return false;
        }
        return true;
    }
};
