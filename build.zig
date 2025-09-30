const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the usb-devices library module
    _ = b.addModule("usb-devices", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create example executable
    const exe = b.addExecutable(.{
        .name = "usb-devices-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // Create daemon executable
    const daemon_exe = b.addExecutable(.{
        .name = "usb-daemon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/daemon_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // Link platform-specific frameworks and libraries
    configurePlatformDependencies(b, daemon_exe, target.result);
    
    b.installArtifact(daemon_exe);

    // Cross-compilation targets
    const cross_step = b.step("cross", "Build for all supported platforms");

    // Build for current platform (native)
    const native_exe = b.addExecutable(.{
        .name = "usb-daemon-native",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/daemon_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    configurePlatformDependencies(b, native_exe, target.result);
    const native_install = b.addInstallArtifact(native_exe, .{});
    cross_step.dependOn(&native_install.step);

    // Cross-compile for other platforms (without platform-specific dependencies)
    const cross_targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
    };

    for (cross_targets) |target_query| {
        const resolved_target = b.resolveTargetQuery(target_query);
        const target_name = b.fmt("usb-daemon-{s}-{s}", .{ @tagName(target_query.cpu_arch.?), @tagName(target_query.os_tag.?) });

        const cross_exe = b.addExecutable(.{
            .name = target_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/daemon_main.zig"),
                .target = resolved_target,
                .optimize = optimize,
            }),
        });

        configurePlatformDependencies(b, cross_exe, resolved_target.result);

        const cross_install = b.addInstallArtifact(cross_exe, .{});
        cross_step.dependOn(&cross_install.step);
    }

    // Create run step for the example
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the USB devices example");
    run_step.dependOn(&run_cmd.step);

    // Create run step for the daemon
    const daemon_run_cmd = b.addRunArtifact(daemon_exe);
    daemon_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        daemon_run_cmd.addArgs(args);
    }

    const daemon_run_step = b.step("daemon", "Run the USB device daemon");
    daemon_run_step.dependOn(&daemon_run_cmd.step);

    // Create unit tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

/// Configure platform-specific dependencies and linking
fn configurePlatformDependencies(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Target) void {
    switch (target.os.tag) {
        .macos => {
            // Only link frameworks when building natively on macOS
            if (@import("builtin").target.os.tag == .macos) {
                exe.linkFramework("IOKit");
                exe.linkFramework("CoreFoundation");
            }
        },
        .linux => {
            exe.linkLibC();
            // Only link udev when building natively on Linux
            if (@import("builtin").target.os.tag == .linux) {
                exe.linkSystemLibrary("udev");
            } else {
                // For cross-compilation, we need to provide stub implementations
                // The actual udev symbols will be resolved at runtime on the target system
                exe.addCSourceFile(.{
                    .file = b.path("src/stubs/udev_stubs.c"),
                    .flags = &[_][]const u8{},
                });
            }
        },
        .windows => {
            exe.linkLibC();
            exe.linkSystemLibrary("ole32");
            exe.linkSystemLibrary("oleaut32");
            exe.linkSystemLibrary("wbemuuid");
        },
        else => {},
    }
}
