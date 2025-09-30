const std = @import("std");
const collector = @import("collector.zig");
const logger = @import("logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    logger.info("USB Device Manager Example", .{});
    
    var usb_collector = collector.UsbDeviceCollector.init(allocator);

    if (!usb_collector.isSupported()) {
        logger.err("USB device collection is not supported on this platform: {any}", .{usb_collector.getPlatform()});
        return;
    }

    logger.info("Platform: {any}", .{usb_collector.getPlatform()});
    logger.info("Collecting USB devices...", .{});

    const devices = usb_collector.listUsbDevices() catch |err| {
        logger.err("Error collecting USB devices: {any}", .{err});
        return;
    };

    defer {
        for (devices) |*device| {
            device.deinit(allocator);
        }
        allocator.free(devices);
    }

    logger.info("Found {} USB device(s):", .{devices.len});

    // Print device information
    for (devices, 0..) |device, i| {
        logger.info("Device {}:", .{i + 1});
        logger.info("  Name: {s}", .{device.name});
        logger.info("  Vendor ID: {s}", .{device.vendor_id});
        logger.info("  Product ID: {s}", .{device.product_id});

        if (device.product_name) |product_name| {
            logger.info("  Product Name: {s}", .{product_name});
        }

        if (device.serial_number) |serial| {
            logger.info("  Serial Number: {s}", .{serial});
        }

        if (device.device_id) |device_id| {
            logger.info("  Device ID: {s}", .{device_id});
        }
    }
}