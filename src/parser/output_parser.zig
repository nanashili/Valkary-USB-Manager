const std = @import("std");
const UsbDevice = @import("../usb_device.zig").UsbDevice;
const Platform = @import("../platform.zig").Platform;

const WindowsParser = @import("windows_parser.zig").WindowsParser;
const LinuxParser = @import("linux_parser.zig").LinuxParser;
const MacParser = @import("mac_parser.zig").MacParser;
const EmptyParser = @import("empty_parser.zig").EmptyParser;

/// Tagged union for platform-specific parsers
pub const OutputParser = union(enum) {
    windows: WindowsParser,
    linux: LinuxParser,
    mac: MacParser,
    empty: EmptyParser,

    /// Parse command output into a list of USB devices
    /// Caller owns the returned slice and must free both the slice and each device
    pub fn parse(self: *OutputParser, allocator: std.mem.Allocator, output: []const u8) ![]UsbDevice {
        return switch (self.*) {
            .windows => |*p| p.parse(allocator, output),
            .linux => |*p| p.parse(allocator, output),
            .mac => |*p| p.parse(allocator, output),
            .empty => |*p| p.parse(allocator, output),
        };
    }

    /// Create a parser for the given platform
    pub fn fromPlatform(platform: Platform) OutputParser {
        return switch (platform) {
            .windows => .{ .windows = WindowsParser{} },
            .linux => .{ .linux = LinuxParser{} },
            .mac => .{ .mac = MacParser{} },
            .unknown => .{ .empty = EmptyParser{} },
        };
    }
};
