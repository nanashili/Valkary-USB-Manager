const std = @import("std");
const collector = @import("collector.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("USB Device Manager Example", .{});
    
    var usb_collector = collector.UsbDeviceCollector.init(allocator);

    if (!usb_collector.isSupported()) {
        std.log.err("USB device collection is not supported on this platform: {any}", .{usb_collector.getPlatform()});
        return;
    }

    std.log.info("Platform: {any}", .{usb_collector.getPlatform()});
    std.log.info("Collecting USB devices...", .{});

    const devices = usb_collector.listUsbDevices() catch |err| {
        std.log.err("Error collecting USB devices: {any}", .{err});
        return;
    };

    defer {
        for (devices) |*device| {
            device.deinit(allocator);
        }
        allocator.free(devices);
    }

    std.log.info("Found {} USB device(s):", .{devices.len});

    for (devices, 0..) |device, i| {
        std.log.info("Device {}:", .{i + 1});
        std.log.info("  Name: {s}", .{device.name});
        std.log.info("  Vendor ID: {s}", .{device.vendor_id});
        std.log.info("  Product ID: {s}", .{device.product_id});
        
        if (device.product_name) |product_name| {
            std.log.info("  Product Name: {s}", .{product_name});
        }
        
        if (device.serial_number) |serial| {
            std.log.info("  Serial Number: {s}", .{serial});
        }
        
        if (device.device_id) |device_id| {
            std.log.info("  Device ID: {s}", .{device_id});
        }
    }
}