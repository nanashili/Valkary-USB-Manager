const std = @import("std");
const UsbDevice = @import("../usb_device.zig").UsbDevice;

/// Parser for Windows wmic output
pub const WindowsParser = struct {
    const NEW_DEVICE_KEY = "Availability";
    const NAME_KEY = "Name";
    const DEVICEID_KEY = "DeviceID";

    pub fn parse(self: *WindowsParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice {
        _ = self;
        var devices = std.array_list.Managed(UsbDevice).init(allocator);
        errdefer {
            for (devices.items) |*device| {
                device.deinit(allocator);
            }
            devices.deinit();
        }

        var current_group = std.array_list.Managed([]const u8).init(allocator);
        defer current_group.deinit();

        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;

            if (std.mem.startsWith(u8, trimmed, NEW_DEVICE_KEY)) {
                if (current_group.items.len > 0) {
                    if (try extractValues(allocator, current_group.items)) |device| {
                        try devices.append(device);
                    }
                    current_group.clearRetainingCapacity();
                }
            }
            try current_group.append(trimmed);
        }

        // Process last group
        if (current_group.items.len > 0) {
            if (try extractValues(allocator, current_group.items)) |device| {
                try devices.append(device);
            }
        }

        return devices.toOwnedSlice();
    }

    fn extractValues(allocator: std.mem.Allocator, lines: []const []const u8) !?UsbDevice {
        var name: ?[]const u8 = null;
        var vendor_id: ?[]const u8 = null;
        var product_id: ?[]const u8 = null;
        var device_id: ?[]const u8 = null;
        var serial_number: ?[]const u8 = null;

        for (lines) |line| {
            if (std.mem.startsWith(u8, line, NAME_KEY)) {
                if (std.mem.indexOfScalar(u8, line, '=')) |idx| {
                    name = try allocator.dupe(u8, line[idx + 1 ..]);
                }
            } else if (std.mem.startsWith(u8, line, DEVICEID_KEY)) {
                if (std.mem.indexOf(u8, line, "VID_")) |vid_idx| {
                    const vid_start = vid_idx + 4;
                    if (vid_start + 4 <= line.len) {
                        vendor_id = try std.fmt.allocPrint(allocator, "0x{s}", .{line[vid_start .. vid_start + 4]});
                    }
                }
                if (std.mem.indexOf(u8, line, "PID_")) |pid_idx| {
                    const pid_start = pid_idx + 4;
                    if (pid_start + 4 <= line.len) {
                        product_id = try std.fmt.allocPrint(allocator, "0x{s}", .{line[pid_start .. pid_start + 4]});

                        const after_pid = line[pid_start + 4 ..];
                        if (after_pid.len > 0 and after_pid[0] == '\\' and std.mem.indexOfScalar(u8, after_pid, '&') == null) {
                            serial_number = try allocator.dupe(u8, after_pid[1..]);
                        }
                    }
                }
                if (std.mem.indexOfScalar(u8, line, '=')) |idx| {
                    const raw_device_id = line[idx + 1 ..];
                    device_id = try processDeviceId(allocator, raw_device_id);
                }
            }
        }

        if (name != null and vendor_id != null and product_id != null) {
            return UsbDevice.init(
                name.?,
                vendor_id.?,
                product_id.?,
                null,
                serial_number,
                device_id,
            );
        }

        // Clean up if we don't have a valid device
        if (name) |n| allocator.free(n);
        if (vendor_id) |v| allocator.free(v);
        if (product_id) |p| allocator.free(p);
        if (device_id) |d| allocator.free(d);
        if (serial_number) |s| allocator.free(s);

        return null;
    }

    fn processDeviceId(allocator: std.mem.Allocator, raw_device_id: []const u8) ![]const u8 {
        var replaced = try allocator.alloc(u8, raw_device_id.len);
        var write_idx: usize = 0;
        var i: usize = 0;

        while (i < raw_device_id.len) {
            if (std.mem.startsWith(u8, raw_device_id[i..], "&amp;")) {
                replaced[write_idx] = '&';
                write_idx += 1;
                i += 5;
            } else if (std.mem.startsWith(u8, raw_device_id[i..], "USB\\")) {
                i += 4;
            } else {
                replaced[write_idx] = raw_device_id[i];
                write_idx += 1;
                i += 1;
            }
        }

        return allocator.realloc(replaced, write_idx);
    }
};
