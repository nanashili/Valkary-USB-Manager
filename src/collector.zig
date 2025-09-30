const std = @import("std");
const UsbDevice = @import("usb_device.zig").UsbDevice;
const Platform = @import("platform.zig").Platform;
const OutputParser = @import("parser/output_parser.zig").OutputParser;

/// Main interface for collecting USB device information
pub const UsbDeviceCollector = struct {
    allocator: std.mem.Allocator,
    platform: Platform,

    /// Initialize a new USB device collector
    pub fn init(allocator: std.mem.Allocator) UsbDeviceCollector {
        return .{
            .allocator = allocator,
            .platform = Platform.current(),
        };
    }

    /// Check if the current platform is supported
    pub fn isSupported(self: *const UsbDeviceCollector) bool {
        return self.platform.isSupported();
    }

    /// Get the current platform
    pub fn getPlatform(self: *const UsbDeviceCollector) Platform {
        return self.platform;
    }

    /// List all connected USB devices
    /// Caller owns the returned slice and must free both the slice and each device
    pub fn listUsbDevices(self: *UsbDeviceCollector) ![]UsbDevice {
        if (!self.platform.isSupported()) {
            return self.allocator.alloc(UsbDevice, 0);
        }

        const command = (try self.platform.getCommand(self.allocator)) orelse {
            return self.allocator.alloc(UsbDevice, 0);
        };
        defer self.allocator.free(command);

        const output = try self.executeCommand(command);
        defer self.allocator.free(output);

        var parser = OutputParser.fromPlatform(self.platform);
        return try parser.parse(self.allocator, output);
    }

    fn executeCommand(self: *UsbDeviceCollector, command: []const u8) ![]u8 {
        var args = std.array_list.Managed([]const u8).init(self.allocator);
        defer args.deinit();

        var tokenizer = std.mem.tokenizeScalar(u8, command, ' ');
        while (tokenizer.next()) |arg| {
            try args.append(arg);
        }

        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        errdefer self.allocator.free(stdout);

        _ = try child.wait();

        return stdout;
    }
};

test "UsbDeviceCollector initialization" {
    const allocator = std.testing.allocator;
    var collector = UsbDeviceCollector.init(allocator);
    _ = collector.isSupported();
    _ = collector.getPlatform();
}
