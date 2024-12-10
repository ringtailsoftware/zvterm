const std = @import("std");

const ZVTerm = @import("zvterm").ZVTerm;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // setup an 80x24 terminal
    var term = try ZVTerm.init(allocator, 80, 24);
    defer term.deinit();
    var writer = term.getWriter();

    // move cursor to x=10,y=10 and write "Hello world"
    try writer.print("\x1b[10;10HHello world", .{});

    // move cursor to x=10,y=12 and write in red
    try writer.print("\x1B[31m\x1b[12;10HThese cells contain red in .fgRGBA", .{});

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Screen contents:\n", .{});

    for (0..term.height) |y| {
        for (0..term.width) |x| {
            const cell = term.getCell(x, y);
            // cell.fgRGBA:u32 holds cell foreground colour
            // cell.bgRGBA:u32 holds cell foreground colour
            // cell.bold:bool holds bold style 

            if (cell.char) |c| {
                try stdout.print("{c}", .{c});
            } else {
                try stdout.print(" ", .{});
            }

        }
        try stdout.print("\n", .{});
    }
    try stdout.print("\n", .{});

}


