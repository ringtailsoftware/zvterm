const std = @import("std");

const terminal = @cImport({
    @cInclude("libvterm/terminal.h");
});

// setup malloc/free functions
const allocFns: terminal.VTermAllocatorFunctions = .{
    .malloc = term_malloc,
    .free = term_free,
};

const alloc_align = std.mem.Alignment.of(usize);
const alloc_metadata_len = std.mem.alignForward(usize, @alignOf(usize), @sizeOf(usize));

fn term_malloc(size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque {
    if (user) |userptr| {
        const self: *ZVTerm = @ptrCast(@alignCast(userptr));
        if (size == 0) {
            return null;
        }
        const full_len = alloc_metadata_len + size;
        const buf = self.allocator.alignedAlloc(u8, alloc_align, full_len) catch |err| switch (err) {
            error.OutOfMemory => return null,
        };
        @as(*usize, @ptrCast(buf)).* = full_len;
        const result = @as([*]align(@alignOf(usize)) u8, @ptrFromInt(@intFromPtr(buf.ptr) + alloc_metadata_len));
        @memset(result[0..size], 0); // zero memory
        return result;
    } else {
        return null;
    }
}

fn getAllocBuf(ptr: [*]u8) []align(@alignOf(usize)) u8 {
    const start = @intFromPtr(ptr) - alloc_metadata_len;
    const len = @as(*usize, @ptrFromInt(start)).*;
    return @alignCast(@as([*]u8, @ptrFromInt(start))[0..len]);
}

fn term_free(ptr: ?*anyopaque, user: ?*anyopaque) callconv(.c) void {
    if (user) |userptr| {
        const self: *ZVTerm = @ptrCast(@alignCast(userptr));
        const p = ptr orelse return;
        self.allocator.free(getAllocBuf(@ptrCast(p)));
    }
}

fn output_callback(s: [*c]const u8, len: usize, user: ?*anyopaque) callconv(.c) void {
    _ = s;
    _ = len;
    _ = user;
    //_ = std.debug.print("output_callback\n", .{}) catch 0;
}

fn damageFn(rect: terminal.VTermRect, user: ?*anyopaque) callconv(.c) c_int {
    if (user) |userptr| {
        const self: *ZVTerm = @ptrCast(@alignCast(userptr));
        self.damage = true;
    }

    _ = rect;
    //_ = std.debug.print("damage\n", .{}) catch 0;
    return 0;
}

fn moverectFn(dest: terminal.VTermRect, src: terminal.VTermRect, user: ?*anyopaque) callconv(.c) c_int {
    _ = dest;
    _ = src;
    _ = user;
    //_ = std.debug.print("moverect\n", .{}) catch 0;
    return 0;
}

fn movecursorFn(pos: terminal.VTermPos, oldpos: terminal.VTermPos, visible: c_int, user: ?*anyopaque) callconv(.c) c_int {
    if (user) |userptr| {
        const self: *ZVTerm = @ptrCast(@alignCast(userptr));
        self.damage = true;
    }

    _ = pos;
    _ = oldpos;
    _ = visible;
    //_ = std.debug.print("movecursor\n", .{}) catch 0;
    return 0;
}

fn settermpropFn(prop: terminal.VTermProp, val: ?*terminal.VTermValue, user: ?*anyopaque) callconv(.c) c_int {
    if (user) |userptr| {
        const self: *ZVTerm = @ptrCast(@alignCast(userptr));

        switch (prop) {
            terminal.VTERM_PROP_CURSORVISIBLE => {
                std.debug.assert(terminal.vterm_get_prop_type(prop) == terminal.VTERM_VALUETYPE_BOOL);
                std.debug.assert(val != null);
                self.cursorvisible = val.?.boolean != 0;
            },
            else => {
                //std.debug.print("settermprop {any}\n", .{prop});
            },
        }
    }
    return 0;
}

fn bellFn(user: ?*anyopaque) callconv(.c) c_int {
    _ = user;
    //_ = std.debug.print("bell\n", .{}) catch 0;
    return 0;
}

fn resizeFn(rows: c_int, cols: c_int, user: ?*anyopaque) callconv(.c) c_int {
    _ = user;
    _ = rows;
    _ = cols;
    //_ = std.debug.print("resize\n", .{}) catch 0;
    return 0;
}

fn sb_pushlineFn(cols: c_int, cells: ?[*]const terminal.VTermScreenCell, user: ?*anyopaque) callconv(.c) c_int {
    _ = cols;
    _ = cells;
    _ = user;
    //_ = std.debug.print("sb_pushlineFn\n", .{}) catch 0;
    return 0;
}

fn sb_poplineFn(cols: c_int, cells: ?[*]terminal.VTermScreenCell, user: ?*anyopaque) callconv(.c) c_int {
    _ = cols;
    _ = cells;
    _ = user;
    //_ = std.debug.print("sb_poplineFn\n", .{}) catch 0;
    return 0;
}

fn sb_clearFn(user: ?*anyopaque) callconv(.c) c_int {
    _ = user;
    //_ = std.debug.print("sb_clear\n", .{}) catch 0;
    return 0;
}

const screen_callbacks: terminal.VTermScreenCallbacks = .{
    .damage = damageFn,
    .moverect = moverectFn,
    .movecursor = movecursorFn,
    .settermprop = settermpropFn,
    .bell = bellFn,
    .resize = resizeFn,
    .sb_pushline = sb_pushlineFn,
    .sb_popline = sb_poplineFn,
    .sb_clear = sb_clearFn,
};

pub const ZVTerm = struct {
    const Self = @This();

    vterm: ?*terminal.VTerm,
    screen: ?*terminal.VTermScreen,
    width: usize,
    height: usize,
    vtw: TermWriter,
    vtwbuf: [4096]u8,
    allocator: std.mem.Allocator,
    cursorvisible: bool,
    damage: bool,

    pub const WriteError = error{ Unsupported, NotConnected };

    pub const TermWriter = struct {
        vterm: ?*terminal.VTerm,
        interface: std.Io.Writer,
        err: ?WriteError = null,

        fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            const wt: *TermWriter = @alignCast(@fieldParentPtr("interface", w));
            var ret: usize = 0;

            const b = w.buffered();
            _ = terminal.vterm_input_write(wt.vterm, b.ptr, b.len);
            _ = w.consume(b.len);

            for (data) |d| {
                _ = terminal.vterm_input_write(wt.vterm, d.ptr, d.len);
                ret += d.len;
            }

            const pattern = data[data.len - 1];
            for (0..splat) |_| {
                _ = terminal.vterm_input_write(wt.vterm, pattern.ptr, pattern.len);
                ret += pattern.len;
            }

            return ret;
        }

        pub fn init(vterm: ?*terminal.VTerm, buf: []u8) TermWriter {
            return TermWriter{
                .vterm = vterm,
                .interface = .{
                    .buffer = buf,
                    .vtable = &.{
                        .drain = drain,
                    },
                },
            };
        }
    };

    pub const Cell = struct {
        pub const RGBACol = packed union {
            raw: u32,
            rgba: packed struct {
                r: u8,
                g: u8,
                b: u8,
                a: u8,
            },
        };

        fg: RGBACol,
        bg: RGBACol,
        bold: bool,
        char: ?u8,
    };

    pub const ZVCursorPos = struct {
        x: usize,
        y: usize,
    };

    pub fn deinit(self: *Self) void {
        terminal.vterm_free(self.vterm);
        self.allocator.destroy(self);
    }

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !*Self {
        const self = try allocator.create(Self);

        // fill out what we can now
        // vterm setup will look at this in current state as userdata
        self.* = .{
            .allocator = allocator,
            .vterm = undefined,
            .screen = undefined,
            .width = width,
            .height = height,
            .vtw = undefined,
            .vtwbuf = undefined,
            .cursorvisible = true,
            .damage = true,
        };

        // use builder interface, so we can supply malloc/free
        const builder: terminal.VTermBuilder = .{
            .ver = 0,
            .rows = @intCast(height),
            .cols = @intCast(width),
            .allocator = &allocFns,
            .allocdata = self,
            .outbuffer_len = 4096,
            .tmpbuffer_len = 4096,
        };
        self.vterm = terminal.vterm_build(&builder);
        self.vtw = TermWriter.init(self.vterm, &self.vtwbuf);

        terminal.vterm_output_set_callback(self.vterm, output_callback, self);
        self.screen = terminal.vterm_obtain_screen(self.vterm);
        terminal.vterm_screen_set_callbacks(self.screen, &screen_callbacks, self);
        terminal.vterm_screen_reset(self.screen, 1);

        return self;
    }

    pub fn getCursorPos(self: *Self) ZVCursorPos {
        var cursorpos: terminal.VTermPos = undefined;
        const state = terminal.vterm_obtain_state(self.vterm);
        terminal.vterm_state_get_cursorpos(state, &cursorpos);
        return .{
            .x = @intCast(cursorpos.col),
            .y = @intCast(cursorpos.row),
        };
    }

    pub fn getCell(self: *Self, x: usize, y: usize) Cell {
        const pos: terminal.VTermPos = .{ .row = @intCast(y), .col = @intCast(x) };
        var cell: terminal.VTermScreenCell = undefined;
        _ = terminal.vterm_screen_get_cell(self.screen, pos, &cell);

        var zvtc: Cell = .{
            .char = null,
            .fg = .{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 0xFF } },
            .bg = .{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 0xFF } },
            .bold = false,
        };

        // FIXME handle unicode
        if (cell.chars[0] != 0) {
            zvtc.char = @intCast(cell.chars[0] & 0xFF);
        }

        if (terminal.VTERM_COLOR_IS_INDEXED(&cell.fg)) {
            terminal.vterm_screen_convert_color_to_rgb(self.screen, &cell.fg);
        }
        if (terminal.VTERM_COLOR_IS_RGB(&cell.fg)) {
            zvtc.fg.rgba.r = cell.fg.rgb.red;
            zvtc.fg.rgba.g = cell.fg.rgb.green;
            zvtc.fg.rgba.b = cell.fg.rgb.blue;
            zvtc.fg.rgba.a = 0xFF;
        }
        if (terminal.VTERM_COLOR_IS_INDEXED(&cell.bg)) {
            terminal.vterm_screen_convert_color_to_rgb(self.screen, &cell.bg);
        }
        if (terminal.VTERM_COLOR_IS_RGB(&cell.bg)) {
            zvtc.bg.rgba.r = cell.bg.rgb.red;
            zvtc.bg.rgba.g = cell.bg.rgb.green;
            zvtc.bg.rgba.b = cell.bg.rgb.blue;
            zvtc.bg.rgba.a = 0xFF;
        }

        zvtc.bold = cell.attrs.bold > 0;
        if (cell.attrs.reverse > 0) { // flip colours
            const tmp = zvtc.bg;
            zvtc.bg = zvtc.fg;
            zvtc.fg = tmp;
        }

        return zvtc;
    }

    pub fn getWriter(self: *Self) *std.Io.Writer {
        return &self.vtw.interface;
    }
};
