const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "600");
    @cDefine("_GNU_SOURCE", {});
    if (builtin.os.tag == .linux)
        @cInclude("pty.h")
    else
        @cInclude("util.h");
    @cInclude("SDL2/SDL.h");
});
const assert = @import("std").debug.assert;
const ZVTerm = @import("zvterm").ZVTerm;
const TrueType = @import("TrueType");

const ROWS: usize = 24;
const COLS: usize = 80;
const SCALE: usize = 1; // SDL renderer upscale
const FONTSIZE: usize = 16;

const WIDTH = COLS * FONTSIZE / 2;
const HEIGHT = ROWS * FONTSIZE;

const Keymap = struct {
    keycode: c.SDL_Keycode,
    data: []const u8,
};

// ctrl + SDL key to escape codes
const ctrlkeymap = [_]Keymap{
    .{ .keycode = c.SDLK_a, .data = "\x01" },
    .{ .keycode = c.SDLK_b, .data = "\x02" },
    .{ .keycode = c.SDLK_c, .data = "\x03" },
    .{ .keycode = c.SDLK_d, .data = "\x04" },
    .{ .keycode = c.SDLK_e, .data = "\x05" },
    .{ .keycode = c.SDLK_f, .data = "\x06" },
    .{ .keycode = c.SDLK_g, .data = "\x07" },
    .{ .keycode = c.SDLK_h, .data = "\x08" },
    .{ .keycode = c.SDLK_i, .data = "\x09" },
    .{ .keycode = c.SDLK_j, .data = "\x0A" },
    .{ .keycode = c.SDLK_k, .data = "\x0B" },
    .{ .keycode = c.SDLK_l, .data = "\x0C" },
    .{ .keycode = c.SDLK_m, .data = "\x0D" },
    .{ .keycode = c.SDLK_n, .data = "\x0E" },
    .{ .keycode = c.SDLK_o, .data = "\x0F" },
    .{ .keycode = c.SDLK_p, .data = "\x10" },
    .{ .keycode = c.SDLK_q, .data = "\x11" },
    .{ .keycode = c.SDLK_r, .data = "\x12" },
    .{ .keycode = c.SDLK_s, .data = "\x13" },
    .{ .keycode = c.SDLK_t, .data = "\x14" },
    .{ .keycode = c.SDLK_u, .data = "\x15" },
    .{ .keycode = c.SDLK_v, .data = "\x16" },
    .{ .keycode = c.SDLK_w, .data = "\x17" },
    .{ .keycode = c.SDLK_z, .data = "\x18" },
    .{ .keycode = c.SDLK_y, .data = "\x19" },
    .{ .keycode = c.SDLK_z, .data = "\x1A" },
    .{ .keycode = c.SDLK_ESCAPE, .data = "\x1B" },
    .{ .keycode = c.SDLK_BACKSLASH, .data = "\x1C" },
};

// SDL key to escape codes
const keymap = [_]Keymap{
    .{ .keycode = c.SDLK_TAB, .data = "\t" },
    .{ .keycode = c.SDLK_ESCAPE, .data = "\x1b" },
    .{ .keycode = c.SDLK_BACKSPACE, .data = "\x7f" },
    .{ .keycode = c.SDLK_UP, .data = "\x1b[A" },
    .{ .keycode = c.SDLK_DOWN, .data = "\x1b[B" },
    .{ .keycode = c.SDLK_RIGHT, .data = "\x1b[C" },
    .{ .keycode = c.SDLK_LEFT, .data = "\x1b[D" },
    .{ .keycode = c.SDLK_PAGEUP, .data = "\x1b[5~" },
    .{ .keycode = c.SDLK_PAGEDOWN, .data = "\x1b[6~" },
    .{ .keycode = c.SDLK_RETURN, .data = "\r" },
    .{ .keycode = c.SDLK_RETURN2, .data = "\r" },
};

const FONT_NUMCHARS = 128;
const FONT_FIRSTCHAR = ' ';

var term: *ZVTerm = undefined;
var termwriter: ZVTerm.TermWriter.Writer = undefined;

// FIXME
fn compat_intCast(comptime T: type, value: anytype) T {
    return @as(T, @intCast(value));
}

fn compat_intToFloat(comptime T: type, value: anytype) T {
    return @as(T, @floatFromInt(value));
}

pub fn drawString(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, font: *const TrueType, str: []const u8, posx: i32, posy: i32, fg: ZVTerm.Cell.RGBACol, bg: ZVTerm.Cell.RGBACol) !void {

_ = renderer;
_ = posx;
_ = posy;
_ = fg;
_ = bg;

    const scale = font.scaleForPixelHeight(FONTSIZE);
    var buffer: std.ArrayListUnmanaged(u8) = undefined;
    defer buffer.deinit(allocator);
    const stdout = std.io.getStdOut().writer();
    var view = try std.unicode.Utf8View.init(str);
    var it = view.iterator();
    while (it.nextCodepoint()) |codepoint| {
        if (font.codepointGlyphIndex(codepoint)) |glyph| {
            std.log.debug("0x{d}: {d}", .{ codepoint, glyph });
            buffer.clearRetainingCapacity();
            const dims = try font.glyphBitmap(allocator, &buffer, glyph, scale, scale);
            const pixels = buffer.items;
            for (0..dims.height) |j| {
                for (0..dims.width) |i| {
                    try stdout.writeByte(" .:ioVM@"[pixels[j * dims.width + i] >> 5]);
                }
                try stdout.writeByte('\n');
            }
        } else {
            std.log.debug("0x{d}: none", .{codepoint});
        }
    }

//    var startx: f32 = compat_intToFloat(f32, posx);
//    var starty: f32 = compat_intToFloat(f32, posy);
//
//    for (str) |b| {
//        if (b < FONT_FIRSTCHAR or b > FONT_FIRSTCHAR + FONT_NUMCHARS) {
//            continue;
//        }
//
//        var q: ttf.stbtt_aligned_quad = undefined;
//        ttf.stbtt_GetBakedQuad(font.bakedChars.ptr, compat_intCast(c_int, font.bakedFontWidth), compat_intCast(c_int, font.bakedFontHeight), b - FONT_FIRSTCHAR, &startx, &starty, &q, 1);
//
//        const dstx: i32 = @intFromFloat(q.x0);
//        const dsty: i32 = @intFromFloat(q.y0);
//
//        const srcx: i32 = @intFromFloat(q.s0 * @as(f32, @floatFromInt(font.bakedFontWidth)));
//        const srcy: i32 = @intFromFloat(q.t0 * @as(f32, @floatFromInt(font.bakedFontHeight)));
//        const srcw: i32 = @intFromFloat((q.s1 - q.s0) * @as(f32, @floatFromInt(font.bakedFontWidth)));
//        const srch: i32 = @intFromFloat((q.t1 - q.t0) * @as(f32, @floatFromInt(font.bakedFontHeight)));
//
//        // srcw,srch == dstw,dsth (but stride is different, src is 8bpp, dst is 32bpp)
//
//        var y: i32 = 0;
//        while (y < srch) : (y += 1) {
//            var x: i32 = 0;
//            while (x < srcw) : (x += 1) {
//                const srcPixVal: u8 = font.bakedFont[
//                    compat_intCast(usize, (srcx + x) +
//                        (srcy + y) * compat_intCast(i32, font.bakedFontWidth))
//                ];
//
//                // break down fgRGBA
//                const r16: u16 = @intCast(fg.rgba.r);
//                const g16: u16 = @intCast(fg.rgba.g);
//                const b16: u16 = @intCast(fg.rgba.b);
//                const a16: u16 = @intCast(fg.rgba.a);
//
//                // multiply by font pixel intensity
//                const fgr: u8 = @intCast((srcPixVal * r16) >> 8);
//                const fgg: u8 = @intCast((srcPixVal * g16) >> 8);
//                const fgb: u8 = @intCast((srcPixVal * b16) >> 8);
//                const fga: u8 = @intCast((srcPixVal * a16) >> 8);
//
//                // break down bgRGBA
//                const bgr: u16 = @intCast(bg.rgba.r);
//                const bgg: u16 = @intCast(bg.rgba.g);
//                const bgb: u16 = @intCast(bg.rgba.b);
//                const bga: u16 = @intCast(bg.rgba.a);
//
//                // blend
//                const r2: u16 = fgr;
//                const g2: u16 = fgg;
//                const b2: u16 = fgb;
//                const a2: u16 = fga;
//                var r1: u16 = @intCast(bgr);
//                var g1: u16 = @intCast(bgg);
//                var b1: u16 = @intCast(bgb);
//                const a1: u16 = @intCast(bga);
//
//                r1 = (r1 * (255 - a2) + r2 * a2) / 255;
//                if (r1 > 255) r1 = 255;
//                g1 = (g1 * (255 - a2) + g2 * a2) / 255;
//                if (g1 > 255) g1 = 255;
//                b1 = (b1 * (255 - a2) + b2 * a2) / 255;
//                if (b1 > 255) b1 = 255;
//
//                _ = c.SDL_SetRenderDrawColor(renderer, @intCast(r1), @intCast(g1), @intCast(b1), @intCast(a1));
//                _ = c.SDL_RenderDrawPoint(renderer, dstx + x, dsty + y);
//            }
//        }
//    }
}

const InputThreadData = struct {
    file: std.fs.File,
    writer: ZVTerm.TermWriter.Writer,
    quit: bool,
};

fn inputThreadFn(userdata: ?*anyopaque) callconv(.C) c_int {
    if (userdata) |p| {
        var inputThreadData: *InputThreadData = @ptrCast(@alignCast(p));

        // poll for incoming data
        // write to term
        // signal SDL to wake main loop
        while (!inputThreadData.quit) {
            var fds = [_]std.posix.pollfd{
                .{
                    .fd = inputThreadData.file.handle,
                    .events = std.posix.POLL.IN,
                    .revents = undefined,
                },
            };
            const ready = std.posix.poll(&fds, 1000) catch 0;
            if (ready == 1) {
                var buf: [4096]u8 = undefined;
                const count = inputThreadData.file.read(&buf) catch 0;
                if (count > 0) {
                    _ = inputThreadData.writer.write(buf[0..count]) catch 0;
                } else {
                    inputThreadData.quit = true;
                }
                // wake SDL
                var event: c.SDL_Event = undefined;
                var userevent: c.SDL_UserEvent = undefined;
                userevent.type = c.SDL_USEREVENT;
                userevent.code = 0;
                userevent.data1 = c.NULL;
                userevent.data2 = c.NULL;
                event.type = c.SDL_USEREVENT;
                event.user = userevent;
                _ = c.SDL_PushEvent(&event);
            }
        }
    }
    return 0;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

//    const gFontSmall = try TrueType.load(@embedFile("pc.ttf"));
    const gFontSmall = try TrueType.load(@embedFile("GoNotoCurrent-Regular.ttf"));
    const gFontSmallBold = try TrueType.load(@embedFile("pc-bold.ttf"));

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("SDLZVTerm", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, WIDTH * SCALE, HEIGHT * SCALE, c.SDL_WINDOW_OPENGL) orelse
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

    _ = c.SDL_RenderSetScale(renderer, SCALE, SCALE);

    term = try ZVTerm.init(allocator, 80, 24);
    defer term.deinit();
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

    var ws: std.posix.winsize = .{
        .ws_col = @intCast(COLS),
        .ws_row = @intCast(ROWS),
        .ws_xpixel = 1,
        .ws_ypixel = 1,
    };

    // Set terminal size. Hack to pass 64bit ioctl op as c_int in Darwin
    const IOCSWINSZ:u64 = 0x80087467;
    const TIOCSWINSZ = if (std.Target.Os.Tag.isDarwin(builtin.target.os.tag)) @as(c_int, @truncate(@as(i64, @bitCast(IOCSWINSZ)))) else std.posix.T.IOCSWINSZ;
    const err = std.posix.system.ioctl(master_pt.handle, TIOCSWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.SetTerminalSizeErr;
    }

    c.SDL_StartTextInput();

    var inputThreadData = InputThreadData{
        .file = master_pt,
        .writer = termwriter,
        .quit = false,
    };
    const inputThread = c.SDL_CreateThread(inputThreadFn, "inputThread", @ptrCast(&inputThreadData));

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_WaitEvent(&event) != 0) {
            // if inputthread requests a quit, also exit main loop
            if (inputThreadData.quit) {
                quit = true;
                break;
            }
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                    break;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.mod & c.KMOD_CTRL > 0) {
                        for (ctrlkeymap) |km| {
                            if (km.keycode == event.key.keysym.sym) {
                                _ = master_pt.write(km.data) catch {
                                    quit = true;
                                };
                            }
                        }
                    }
                    for (keymap) |km| {
                        if (km.keycode == event.key.keysym.sym) {
                            _ = master_pt.write(km.data) catch {
                                quit = true;
                            };
                        }
                    }
                },
                c.SDL_TEXTINPUT => {
                    const c_string: [*c]const u8 = &event.text.text;
                    _ = try master_pt.write(std.mem.span(c_string));
                },

                else => {},
            }

            if (term.damage) {
                term.damage = false;
                _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
                _ = c.SDL_RenderClear(renderer);

                const cursorPos = term.getCursorPos();

                for (0..ROWS) |y| {
                    for (0..COLS) |x| {
                        const cell = term.getCell(x, y);
                        _ = c.SDL_SetRenderDrawColor(renderer, cell.bg.rgba.r, cell.bg.rgba.g, cell.bg.rgba.b, 0xFF);
                        var rect: c.SDL_Rect = undefined;
                        rect.x = @intCast(x * FONTSIZE / 2);
                        rect.y = @intCast(y * FONTSIZE);
                        rect.w = FONTSIZE / 2;
                        rect.h = FONTSIZE;
                        _ = c.SDL_RenderFillRect(renderer, &rect);

                        if (cell.char) |ch| {
                            var font: *const TrueType = &gFontSmall;
                            if (cell.bold) {
                                font = &gFontSmallBold;
                            }

                            const yo: i32 = -4;
                            try drawString(allocator, renderer, font, &.{ch}, @intCast(x * FONTSIZE / 2), @as(i32, @intCast(y * FONTSIZE + FONTSIZE)) + yo, cell.fg, cell.bg);
                        }
                        if (term.cursorvisible and x == cursorPos.x and y == cursorPos.y) {
                            _ = c.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
                            rect.x = @intCast(x * FONTSIZE / 2);
                            rect.y = @intCast(y * FONTSIZE);
                            rect.w = FONTSIZE / 2;
                            rect.h = FONTSIZE;
                            _ = c.SDL_RenderFillRect(renderer, &rect);
                        }
                    }
                }

                c.SDL_RenderPresent(renderer);
            }
        }
    }

    // signal inputthread to stop
    inputThreadData.quit = true;
    c.SDL_DetachThread(@constCast(inputThread));
}
