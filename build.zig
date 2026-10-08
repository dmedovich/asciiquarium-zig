const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "asciiquarium-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    b.installArtifact(exe);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run regression tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
