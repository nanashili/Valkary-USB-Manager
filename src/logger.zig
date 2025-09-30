const std = @import("std");

/// Log level configuration
pub const LogLevel = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
    
    pub fn fromString(str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, str, "debug")) {
            return .debug;
        } else if (std.mem.eql(u8, str, "info")) {
            return .info;
        } else if (std.mem.eql(u8, str, "warn")) {
            return .warn;
        } else if (std.mem.eql(u8, str, "error")) {
            return .err;
        }
        return null;
    }
    
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .err => "error",
        };
    }
};

/// Global log level setting
var global_log_level: LogLevel = .info;

/// Set the global log level
pub fn setLogLevel(level: LogLevel) void {
    global_log_level = level;
}

/// Get the current log level
pub fn getLogLevel() LogLevel {
    return global_log_level;
}

/// Check if a log level should be printed
fn shouldLog(level: LogLevel) bool {
    return @intFromEnum(level) >= @intFromEnum(global_log_level);
}

/// Custom debug logging function
pub fn debug(comptime format: []const u8, args: anytype) void {
    if (shouldLog(.debug)) {
        std.log.debug(format, args);
    }
}

/// Custom info logging function
pub fn info(comptime format: []const u8, args: anytype) void {
    if (shouldLog(.info)) {
        std.log.info(format, args);
    }
}

/// Custom warn logging function
pub fn warn(comptime format: []const u8, args: anytype) void {
    if (shouldLog(.warn)) {
        std.log.warn(format, args);
    }
}

/// Custom error logging function
pub fn err(comptime format: []const u8, args: anytype) void {
    if (shouldLog(.err)) {
        std.log.err(format, args);
    }
}

/// Convenience function to log with explicit level
pub fn log(level: LogLevel, comptime format: []const u8, args: anytype) void {
    switch (level) {
        .debug => debug(format, args),
        .info => info(format, args),
        .warn => warn(format, args),
        .err => err(format, args),
    }
}