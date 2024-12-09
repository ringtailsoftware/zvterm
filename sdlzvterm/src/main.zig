const std = @import("std");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "600");
    @cDefine("_GNU_SOURCE", {});
    @cInclude("util.h"); // pty.h on linux?
    @cInclude("SDL2/SDL.h");
});
const assert = @import("std").debug.assert;
const ZVTerm = @import("zvterm").ZVTerm;

const ttf = @cImport({
    @cInclude("stb_truetype.h");
});

const ROWS: usize = 24;
const COLS: usize = 80;
const FONTSIZE: usize = 16;

const WIDTH = COLS * FONTSIZE / 2;
const HEIGHT = ROWS * FONTSIZE;

const FONT_NUMCHARS = 128;
const FONT_FIRSTCHAR = ' ';

var term: ZVTerm = undefined;
var termwriter: ZVTerm.TermWriter.Writer = undefined;

// FIXME
fn compat_intCast(comptime T: type, value: anytype) T {
    return @as(T, @intCast(value));
}

fn compat_intToFloat(comptime T: type, value: anytype) T {
    return @as(T, @floatFromInt(value));
}

pub const Font = struct {
    const Self = @This();

    bakedFontWidth: usize,
    bakedFontHeight: usize,
    bakedFont: []u8,
    bakedChars: []ttf.stbtt_bakedchar,
    pixelSize: usize,

    pub fn init(al: std.mem.Allocator, comptime ttfname: []const u8, pixelSize: usize) !Self {
        const bakedFontWidth: usize = FONT_NUMCHARS * pixelSize;
        const bakedFontHeight: usize = FONT_NUMCHARS * pixelSize;

        const bakedFont = al.alloc(u8, bakedFontWidth * bakedFontHeight) catch |err| {
            return err;
        };
        const bakedChars = al.alloc(ttf.stbtt_bakedchar, FONT_NUMCHARS) catch |err| {
            return err;
        };

        const fontData = @embedFile(ttfname);

        const ret = ttf.stbtt_BakeFontBitmap(@as([*]u8, @ptrCast(@constCast(fontData))), 0, @floatFromInt(pixelSize), bakedFont.ptr, @intCast(bakedFontWidth), @intCast(bakedFontHeight), FONT_FIRSTCHAR, FONT_NUMCHARS, bakedChars.ptr);
        if (ret <= 0) {
            std.log.err("BakeFontBitmap ret={d}", .{ret});
            return error.FontInitFailed;
        }

        return Self{
            .bakedFont = bakedFont,
            .bakedChars = bakedChars,
            .pixelSize = pixelSize,
            .bakedFontWidth = bakedFontWidth,
            .bakedFontHeight = bakedFontHeight,
        };
    }
};

pub fn drawString(renderer: *c.SDL_Renderer, font: *Font, str: []const u8, posx: i32, posy: i32, colour: u32) void {
    var startx: f32 = compat_intToFloat(f32, posx);
    var starty: f32 = compat_intToFloat(f32, posy);

    for (str) |b| {
        if (b - FONT_FIRSTCHAR > FONT_NUMCHARS) {
            continue;
        }

        var q: ttf.stbtt_aligned_quad = undefined;
        ttf.stbtt_GetBakedQuad(font.bakedChars.ptr, compat_intCast(c_int, font.bakedFontWidth), compat_intCast(c_int, font.bakedFontHeight), b - FONT_FIRSTCHAR, &startx, &starty, &q, 1);

        const dstx: i32 = @intFromFloat(q.x0);
        const dsty: i32 = @intFromFloat(q.y0);

        const srcx: i32 = @intFromFloat(q.s0 * @as(f32, @floatFromInt(font.bakedFontWidth)));
        const srcy: i32 = @intFromFloat(q.t0 * @as(f32, @floatFromInt(font.bakedFontHeight)));
        const srcw: i32 = @intFromFloat((q.s1 - q.s0) * @as(f32, @floatFromInt(font.bakedFontWidth)));
        const srch: i32 = @intFromFloat((q.t1 - q.t0) * @as(f32, @floatFromInt(font.bakedFontHeight)));

        // srcw,srch == dstw,dsth (but stride is different, src is 8bpp, dst is 32bpp)

        var y: i32 = 0;
        while (y < srch) : (y += 1) {
            var x: i32 = 0;
            while (x < srcw) : (x += 1) {
                const srcPixVal: u8 = font.bakedFont[
                    compat_intCast(usize, (srcx + x) +
                        (srcy + y) * compat_intCast(i32, font.bakedFontWidth))
                ];

                const r16 = compat_intCast(u16, (colour & 0x000000FF) >> 0);
                const g16 = compat_intCast(u16, (colour & 0x0000FF00) >> 8);
                const b16 = compat_intCast(u16, (colour & 0x00FF0000) >> 16);
                const a16 = compat_intCast(u16, (colour & 0xFF000000) >> 24);

                const dr: u8 = @intCast((srcPixVal * r16) >> 8);
                const dg: u8 = @intCast((srcPixVal * g16) >> 8);
                const db: u8 = @intCast((srcPixVal * b16) >> 8);
                const da: u8 = @intCast((srcPixVal * a16) >> 8);

                _ = c.SDL_SetRenderDrawColor(renderer, dr, dg, db, da);
                _ = c.SDL_RenderDrawPoint(renderer, dstx + x, dsty + y);
            }
        }
    }
}

fn timer_cb(interval:u32, userdata:?*anyopaque) callconv(.C) u32 {
    _ = userdata;
    var event:c.SDL_Event = undefined;
    var userevent:c.SDL_UserEvent = undefined;

    userevent.type = c.SDL_USEREVENT;
    userevent.code = 0;
    userevent.data1 = c.NULL;
    userevent.data2 = c.NULL;

    event.type = c.SDL_USEREVENT;
    event.user = userevent;

    _ = c.SDL_PushEvent(&event);
    return interval;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var gFontSmall = try Font.init(allocator, "pc.ttf", FONTSIZE);
    var gFontSmallBold = try Font.init(allocator, "pc-bold.ttf", FONTSIZE);

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("SDLZVTerm", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, WIDTH, HEIGHT, c.SDL_WINDOW_OPENGL) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    term = try ZVTerm.init(80, 24);
    termwriter = term.getWriter();

    // Create key=val pairs from environment
    // https://github.com/amesaine/terminal-emulator/blob/ad0f2183259e5a2ff717fa1b7842dd76da271d57/src/terminal.zig#L61
    var map = try std.process.getEnvMap(allocator);
    defer map.deinit();
    const max_env = 1000;
    var env: [max_env:null]?[*:0]u8 = undefined;

    var i: usize = 0;
    var iter = map.iterator();
    while (iter.next()) |entry| : (i += 1) {
        const keyval = try std.fmt.allocPrintZ(
            allocator,
            "{s}={s}",
            .{ entry.key_ptr.*, entry.value_ptr.* },
        );
        env[i] = keyval;
    } else {
        env[i] = null;
    }

    // forkpty
    var master_pt = std.fs.File{ .handle = undefined };
    const pid = c.forkpty(&master_pt.handle, null, null, null);
    if (pid < 0) {
        @panic("forkpty failed");
    } else if (pid == 0) {
        const args = [_:null]?[*:0]u8{
            @constCast("bash"),
            null,
        };

        std.posix.execvpeZ(args[0].?, &args, &env) catch unreachable;
        std.process.cleanExit();
    }

    c.SDL_StartTextInput();

    // Ugly, but works - add a timer pushing events so event loop constantly polls
    _ = c.SDL_AddTimer(50, timer_cb, null);

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_TAB => {
                            _ = try master_pt.write("\t");
                        },
                        c.SDLK_ESCAPE => {
                            _ = try master_pt.write("\x1b[A");
                        },
                        c.SDLK_BACKSPACE => {
                            _ = try master_pt.write("\x7f");
                        },
                        c.SDLK_UP => {
                            _ = try master_pt.write("\x1b[A");
                        },
                        c.SDLK_DOWN => {
                            _ = try master_pt.write("\x1b[B");
                        },
                        c.SDLK_RIGHT => {
                            _ = try master_pt.write("\x1b[C");
                        },
                        c.SDLK_LEFT => {
                            _ = try master_pt.write("\x1b[D");
                        },
                        c.SDLK_RETURN, c.SDLK_RETURN2 => {
                            _ = try master_pt.write("\r");
                        },
                        else => {},
                    }
                },
                c.SDL_TEXTINPUT => {
                    const c_string: [*c]const u8 = &event.text.text;
                    _ = try master_pt.write(std.mem.span(c_string));
                },

                else => {},
            }

            var fds = [_]std.posix.pollfd{
                .{
                    .fd = master_pt.handle,
                    .events = std.posix.POLL.IN,
                    .revents = undefined,
                },
            };
            const ready = try std.posix.poll(&fds, 0);
            if (ready == 1) {
                var buf: [4096]u8 = undefined;
                const count = try master_pt.read(&buf);
                if (count > 0) {
                    _ = try termwriter.write(buf[0..count]);
                }
            }

            _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
            _ = c.SDL_RenderClear(renderer);

            const cursorPos = term.getCursorPos();

            for (0..ROWS) |y| {
                for (0..COLS) |x| {
                    const cell = term.getCell(x, y);
                    if (cell.char) |ch| {
                        var font: *Font = &gFontSmall;
                        if (cell.bold) {
                            font = &gFontSmallBold;
                        }

                        const yo: i32 = -4;
                        drawString(renderer, font, &.{ch}, @intCast(x * FONTSIZE / 2), @as(i32, @intCast(y * FONTSIZE + FONTSIZE)) + yo, cell.fgRGBA);
                    }
                    if (x == cursorPos.x and y == cursorPos.y) {
                        _ = c.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
                        var rect:c.SDL_Rect = undefined;
                        rect.x = @intCast(x * FONTSIZE/2);
                        rect.y = @intCast(y * FONTSIZE);
                        rect.w = FONTSIZE/2;
                        rect.h = FONTSIZE;
                        _ = c.SDL_RenderFillRect(renderer, &rect);
                    }

                }
            }

            c.SDL_RenderPresent(renderer);
        }

        c.SDL_Delay(17);
    }
}
