const std = @import("std");
const builtin = @import("builtin");

/// Represents the operating system platform
pub const Platform = enum {
    windows,
    linux,
    mac,
    unknown,

    /// Detect the current platform
    pub fn current() Platform {
        return switch (builtin.os.tag) {
            .windows => .windows,
            .linux => .linux,
            .macos => .mac,
            else => .unknown,
        };
    }

    /// Check if the platform is supported for USB device detection
    pub fn isSupported(self: Platform) bool {
        return self != .unknown;
    }

    /// Get the command to execute for USB device detection on this platform
    /// Caller owns the returned memory
    pub fn getCommand(self: Platform, allocator: std.mem.Allocator) !?[]const u8 {
        return switch (self) {
            .windows => blk: {
                const windir = std.process.getEnvVarOwned(allocator, "WINDIR") catch "C:\\Windows";
                defer allocator.free(windir);
                break :blk try std.fmt.allocPrint(
                    allocator,
                    "{s}\\system32\\wbem\\wmic path CIM_LogicalDevice where \"DeviceID like 'USB\\\\%'\" get /value",
                    .{windir},
                );
            },
            .linux => try allocator.dupe(u8, "lsusb -v"),
            .mac => try allocator.dupe(u8, "ioreg -p IOUSB -l -w 0"),
            .unknown => null,
        };
    }
};

test "Platform detection" {
    const platform = Platform.current();
    try std.testing.expect(platform == .windows or
        platform == .linux or
        platform == .mac or
        platform == .unknown);
}

test "Platform support check" {
    const platform = Platform.current();
    if (platform != .unknown) {
        try std.testing.expect(platform.isSupported());
    }
}

test "Platform command generation" {
    const allocator = std.testing.allocator;
    const platform = Platform.current();

    if (platform.isSupported()) {
        const command = try platform.getCommand(allocator);
        defer if (command) |cmd| allocator.free(cmd);
        try std.testing.expect(command != null);
    }
}
