const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mcz_mod = b.addModule("mcz", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_step = b.step("example", "Run example");
    const example_exe = b.addExecutable(.{
        .name = "mcz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "mcz", .module = mcz_mod }},
        }),
    });
    const example_run = b.addRunArtifact(example_exe);
    example_step.dependOn(&example_run.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = mcz_mod,
    });
    const test_cmd = b.addRunArtifact(unit_tests);
    test_step.dependOn(&test_cmd.step);

    const docs_step = b.step("docs", "Build docs");
    const docs_obj = b.addObject(.{
        .name = "mcz",
        .root_module = mcz_mod,
    });
    const docs = docs_obj.getEmittedDocs();
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);
}
