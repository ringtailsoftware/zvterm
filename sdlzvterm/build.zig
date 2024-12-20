const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sdlzvterm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe.addIncludePath(b.path("src/"));

    if (b.systemIntegrationOption("sdl2", .{})) {
        exe.linkSystemLibrary("SDL2");
    } else {
        const sdl_dep = b.dependency("SDL", .{
            .optimize = .ReleaseFast,
            .target = target,
        });
        exe.linkLibrary(sdl_dep.artifact("SDL2"));
    }
    const zvterm_dep = b.dependency("zvterm", .{
        .target = target,
        .optimize = optimize,
    });
    const zvterm_mod = zvterm_dep.module("zvterm");
    exe.root_module.addImport("zvterm", zvterm_mod);

    const TrueType_dep = b.dependency("TrueType", .{
        .target = target,
        .optimize = optimize,
    });
    const TrueType_mod = TrueType_dep.module("TrueType");
    exe.root_module.addImport("TrueType", TrueType_mod);

    b.installArtifact(exe);

    const run = b.step("run", "Run the demo");
    const run_cmd = b.addRunArtifact(exe);
    run.dependOn(&run_cmd.step);
}
