const std = @import("std");

const terminal = @cImport({
    @cInclude("libvterm/terminal.h");
});

fn output_callback(s:[*c]const u8, len:usize, user:?*anyopaque) callconv(.C) void {
    _ = s;
    _ = len;
    _ = user;
    //_ = std.debug.print("output_callback\n", .{}) catch 0;
}

fn damageFn(rect:terminal.VTermRect, user:?*anyopaque) callconv(.C) c_int {
    _ = rect;
    _ = user;
    //_ = std.debug.print("damage\n", .{}) catch 0;
    return 0;
}

fn moverectFn(dest:terminal.VTermRect, src:terminal.VTermRect, user:?*anyopaque) callconv(.C) c_int {
    _ = dest;
    _ = src;
    _ = user;
    //_ = std.debug.print("moverect\n", .{}) catch 0;
    return 0;
}

fn movecursorFn(pos:terminal.VTermPos, oldpos:terminal.VTermPos, visible:c_int, user:?*anyopaque) callconv(.C) c_int {
    _ = pos;
    _ = oldpos;
    _ = visible;
    _ = user;
    //_ = std.debug.print("movecursor\n", .{}) catch 0;
    return 0;
}

fn settermpropFn(prop:terminal.VTermProp, val:?*terminal.VTermValue, user:?*anyopaque) callconv(.C) c_int {
    _ = prop;
    _ = val;
    _ = user;
    //_ = std.debug.print("settermprop\n", .{}) catch 0;
    return 0;
}

fn bellFn(user:?*anyopaque) callconv(.C) c_int {
    _ = user;
    //_ = std.debug.print("bell\n", .{}) catch 0;
    return 0;
}

fn resizeFn(rows:c_int, cols:c_int, user:?*anyopaque) callconv(.C) c_int {
    _ = user;
    _ = rows;
    _ = cols;
    //_ = std.debug.print("resize\n", .{}) catch 0;
    return 0;
}

fn sb_pushlineFn(cols:c_int, cells:?[*]const terminal.VTermScreenCell, user:?*anyopaque) callconv(.C) c_int {
    _ = cols;
    _ = cells;
    _ = user;
    //_ = std.debug.print("sb_pushlineFn\n", .{}) catch 0;
    return 0;
}

fn sb_poplineFn(cols:c_int, cells:?[*]terminal.VTermScreenCell, user:?*anyopaque) callconv(.C) c_int {
    _ = cols;
    _ = cells;
    _ = user;
    //_ = std.debug.print("sb_poplineFn\n", .{}) catch 0;
    return 0;
}

fn sb_clearFn(user:?*anyopaque) callconv(.C) c_int {
    _ = user;
    //_ = std.debug.print("sb_clear\n", .{}) catch 0;
    return 0;
}

const screen_callbacks:terminal.VTermScreenCallbacks = .{
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

    pub const TermWriter = struct {
        pub const Writer = std.io.Writer(
            *TermWriter,
            error{},
            write,
        );
        pub const Error = anyerror;
        vterm: ?*terminal.VTerm,

        pub fn writeAll(self: *const TermWriter, data: []const u8) error{}!void {
            _ = try write(self, data);
        }

        pub fn write(self: *const TermWriter, data: []const u8) error{}!usize {
            _ = terminal.vterm_input_write(self.vterm, data.ptr, data.len);
            return data.len;
        }

        pub fn writer(self: *TermWriter) Writer {
            return .{ .context = self };
        }
    };


    vterm:?*terminal.VTerm,
    screen:?*terminal.VTermScreen,
    width: usize,
    height: usize,
    vtw: TermWriter,

    pub const ZVTermCell = struct {
        fgRGBA: u32,
        bgRGBA: u32,
        bold: bool,
        char: ?u8,
    };

    pub const ZVCursorPos = struct {
        x: usize,
        y: usize,
    };

    pub fn init(width:usize, height:usize) !Self {
        const vterm = terminal.vterm_new(@intCast(height), @intCast(width));
        terminal.vterm_output_set_callback(vterm, output_callback, null);
        const screen = terminal.vterm_obtain_screen(vterm);
        terminal.vterm_screen_set_callbacks(screen, &screen_callbacks, null);
        terminal.vterm_screen_reset(screen, 1);

        return Self {
            .vterm = vterm,
            .screen = screen,
            .width = width,
            .height = height,
            .vtw = TermWriter{.vterm = vterm},
        };
    }

    pub fn getCursorPos(self:*Self) ZVCursorPos {
        var cursorpos:terminal.VTermPos = undefined;
        const state = terminal.vterm_obtain_state(self.vterm);
        terminal.vterm_state_get_cursorpos(state, &cursorpos);
        return .{
            .x = @intCast(cursorpos.col),
            .y = @intCast(cursorpos.row),
        };
    }

    pub fn getCell(self:*Self, x:usize, y:usize) ZVTermCell {
        const pos:terminal.VTermPos = .{.row=@intCast(y), .col=@intCast(x)};
        var cell:terminal.VTermScreenCell = undefined;
        _ = terminal.vterm_screen_get_cell(self.screen, pos, &cell);

        var zvtc:ZVTermCell = .{ 
            .char = null,
            .fgRGBA = 0,
            .bgRGBA = 0,
            .bold = false,
        };

        // FIXME handle unicode
        if (cell.chars[0] != 0) {
            zvtc.char = @intCast(cell.chars[0] & 0xFF);
        }

        if (terminal.VTERM_COLOR_IS_INDEXED(&cell.fg)) {
            terminal.vterm_screen_convert_color_to_rgb(self.screen, &cell.fg)
;
        }
        if (terminal.VTERM_COLOR_IS_RGB(&cell.fg)) {
            zvtc.fgRGBA = @as(u32, @intCast(0xFF)) << 24 | @as(u32, @intCast(cell.fg.rgb.blue)) << 16 | @as(u32, @intCast(cell.fg.rgb.green)) << 8 | @as(u32, @intCast(cell.fg.rgb.red));
        }
        if (terminal.VTERM_COLOR_IS_INDEXED(&cell.bg)) {
            terminal.vterm_screen_convert_color_to_rgb(self.screen, &cell.bg)
;
        }
        if (terminal.VTERM_COLOR_IS_RGB(&cell.bg)) {
            zvtc.bgRGBA = @as(u32, @intCast(0xFF)) << 24 | @as(u32, @intCast(cell.bg.rgb.blue)) << 16 | @as(u32, @intCast(cell.bg.rgb.green)) << 8 | @as(u32, @intCast(cell.bg.rgb.red));
        }

        zvtc.bold = cell.attrs.bold > 0;
        if (cell.attrs.reverse > 0) {   // flip colours
            const tmp = zvtc.bgRGBA;
            zvtc.bgRGBA = zvtc.fgRGBA;
            zvtc.fgRGBA = tmp;
        }

        return zvtc;
    }

    pub fn deinit(self:*Self) void {
        terminal.vterm_free(self.vterm);
    }

    pub fn getWriter(self:*Self) TermWriter.Writer {
        return self.vtw.writer();
    }
};

