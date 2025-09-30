const std = @import("std");

/// Represents a USB device with essential information
pub const UsbDevice = struct {
    name: []const u8,
    vendor_id: []const u8,
    product_id: []const u8,
    product_name: ?[]const u8,
    serial_number: ?[]const u8,
    device_id: ?[]const u8,

    /// Initialize a USB device
    pub fn init(
        name: []const u8,
        vendor_id: []const u8,
        product_id: []const u8,
        product_name: ?[]const u8,
        serial_number: ?[]const u8,
        device_id: ?[]const u8,
    ) UsbDevice {
        return UsbDevice{
            .name = name,
            .vendor_id = vendor_id,
            .product_id = product_id,
            .product_name = product_name,
            .serial_number = serial_number,
            .device_id = device_id,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *UsbDevice, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.vendor_id);
        allocator.free(self.product_id);
        if (self.product_name) |product_name| {
            allocator.free(product_name);
        }
        if (self.serial_number) |serial_number| {
            allocator.free(serial_number);
        }
        if (self.device_id) |device_id| {
            allocator.free(device_id);
        }
    }
};

test "UsbDevice init and deinit" {
    const allocator = std.testing.allocator;

    const name = try allocator.dupe(u8, "Test Device");
    const vendor = try allocator.dupe(u8, "0x1234");
    const product = try allocator.dupe(u8, "0x5678");

    var device = UsbDevice.init(name, vendor, product, null, null, null);
    device.deinit(allocator);
}
