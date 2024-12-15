const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zvterm_mod = b.addModule("zvterm", .{
        .root_source_file = b.path("src/zvterm.zig"),
    });

    zvterm_mod.addCSourceFiles(.{
        .files = &.{ "src/libvterm/terminal.c", "src/libvterm/encoding.c", "src/libvterm/mouse.c", "src/libvterm/pen.c", "src/libvterm/state.c", "src/libvterm/vterm.c", "src/libvterm/keyboard.c", "src/libvterm/parser.c", "src/libvterm/screen.c", "src/libvterm/unicode.c" },
        .flags = &.{"-Wall"},
    });
    zvterm_mod.addIncludePath(b.path("src/"));

    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // examples
    const examples = [_][]const u8{
        "helloworld",
    };

    for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
        });
        example.addIncludePath(b.path("examples/"));
        example.addIncludePath(b.path("src/"));
        example.addIncludePath(b.path("../src/"));
        example.linkLibC();

        const install_example = b.addRunArtifact(example);
        example.root_module.addImport(
            "zvterm",
            zvterm_mod,
        );

        const example_step = b.step(example_name, b.fmt("Run {s} example", .{example_name}));
        example_step.dependOn(&install_example.step);
        example_step.dependOn(&example.step);
    }
}
