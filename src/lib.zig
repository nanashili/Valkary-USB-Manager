pub const UsbDevice = @import("usb_device.zig").UsbDevice;
pub const Platform = @import("platform.zig").Platform;
pub const UsbDeviceCollector = @import("collector.zig").UsbDeviceCollector;

// Re-export parsers for advanced usage
pub const parsers = struct {
    pub const OutputParser = @import("parser/output_parser.zig").OutputParser;
    pub const EmptyParser = @import("parser/empty_parser.zig").EmptyParser;
    pub const WindowsParser = @import("parser/windows_parser.zig").WindowsParser;
    pub const LinuxParser = @import("parser/linux_parser.zig").LinuxParser;
    pub const MacParser = @import("parser/mac_parser.zig").MacParser;
};

test {
    @import("std").testing.refAllDecls(@This());
}
