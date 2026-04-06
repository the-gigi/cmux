const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (b.lazyDependency("ghostty", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        mod.addImport("ghostty-vt", dep.module("ghostty-vt"));
    }

    const lib = b.addLibrary(.{
        .name = "cmux-ghostty-shim",
        .linkage = .dynamic,
        .root_module = mod,
    });
    lib.linkLibC();
    lib.linkLibCpp();
    b.installArtifact(lib);
}
