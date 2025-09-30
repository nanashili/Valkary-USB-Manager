const std = @import("std");
const UsbDevice = @import("../usb_device.zig").UsbDevice;

/// Placeholder parser that returns an empty list
/// Used for unsupported platforms
pub const EmptyParser = struct {
    pub fn parse(_: *EmptyParser, allocator: std.mem.Allocator, _: []const u8) ![]UsbDevice {
        return allocator.alloc(UsbDevice, 0);
    }
};
