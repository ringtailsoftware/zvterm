const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "600");
    @cDefine("_GNU_SOURCE", {});
    if (builtin.os.tag == .linux)
        @cInclude("pty.h")
    else
        @cInclude("util.h");
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    // For programs that provide their own entry points instead of relying on SDL's main function
    // macro magic, 'SDL_MAIN_HANDLED' should be defined before including 'SDL_main.h'.
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});
const assert = @import("std").debug.assert;
const ZVTerm = @import("zvterm").ZVTerm;
const TrueType = @import("TrueType");

const ROWS: usize = 24;
const COLS: usize = 80;
const SCALE: usize = 1; // SDL renderer upscale
const FONTSIZE: usize = 16;

const BORDER = 16;
const WIDTH = (COLS * FONTSIZE / 2) + BORDER;
const HEIGHT = (ROWS * FONTSIZE) + BORDER;

const Keymap = struct {
    keycode: c.SDL_Keycode,
    data: []const u8,
};

// ctrl + SDL key to escape codes
const ctrlkeymap = [_]Keymap{
    .{ .keycode = c.SDLK_A, .data = "\x01" },
    .{ .keycode = c.SDLK_B, .data = "\x02" },
    .{ .keycode = c.SDLK_C, .data = "\x03" },
    .{ .keycode = c.SDLK_D, .data = "\x04" },
    .{ .keycode = c.SDLK_E, .data = "\x05" },
    .{ .keycode = c.SDLK_F, .data = "\x06" },
    .{ .keycode = c.SDLK_G, .data = "\x07" },
    .{ .keycode = c.SDLK_H, .data = "\x08" },
    .{ .keycode = c.SDLK_I, .data = "\x09" },
    .{ .keycode = c.SDLK_J, .data = "\x0A" },
    .{ .keycode = c.SDLK_K, .data = "\x0B" },
    .{ .keycode = c.SDLK_L, .data = "\x0C" },
    .{ .keycode = c.SDLK_M, .data = "\x0D" },
    .{ .keycode = c.SDLK_N, .data = "\x0E" },
    .{ .keycode = c.SDLK_O, .data = "\x0F" },
    .{ .keycode = c.SDLK_P, .data = "\x10" },
    .{ .keycode = c.SDLK_Q, .data = "\x11" },
    .{ .keycode = c.SDLK_R, .data = "\x12" },
    .{ .keycode = c.SDLK_S, .data = "\x13" },
    .{ .keycode = c.SDLK_T, .data = "\x14" },
    .{ .keycode = c.SDLK_U, .data = "\x15" },
    .{ .keycode = c.SDLK_V, .data = "\x16" },
    .{ .keycode = c.SDLK_W, .data = "\x17" },
    .{ .keycode = c.SDLK_X, .data = "\x18" },
    .{ .keycode = c.SDLK_Y, .data = "\x19" },
    .{ .keycode = c.SDLK_Z, .data = "\x1A" },
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

pub fn drawString(gpa: std.mem.Allocator, renderer: *c.SDL_Renderer, font: *const TrueType, str: []const u8, posx: i32, posy: i32, fg: ZVTerm.Cell.RGBACol, bg: ZVTerm.Cell.RGBACol) !void {
    const scale = font.scaleForPixelHeight(FONTSIZE);

    for (str) |b| {
        if (b < FONT_FIRSTCHAR or b > FONT_FIRSTCHAR + FONT_NUMCHARS) {
            continue;
        }

        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(gpa);
        buffer.clearRetainingCapacity();
        if (font.codepointGlyphIndex(b)) |glyph| {
            const dims = font.glyphBitmap(gpa, &buffer, glyph, scale, scale) catch continue;
            const pixels = buffer.items;

            var y: i32 = 0;
            while (y < dims.height) : (y += 1) {
                var x: i32 = 0;
                while (x < dims.width) : (x += 1) {
                    const srcPixVal: u8 = pixels[@intCast(x + y * dims.width)];

                    // break down fgRGBA
                    const r16: u16 = @intCast(fg.rgba.r);
                    const g16: u16 = @intCast(fg.rgba.g);
                    const b16: u16 = @intCast(fg.rgba.b);
                    const a16: u16 = @intCast(fg.rgba.a);

                    // multiply by font pixel intensity
                    const fgr: u8 = @intCast((srcPixVal * r16) >> 8);
                    const fgg: u8 = @intCast((srcPixVal * g16) >> 8);
                    const fgb: u8 = @intCast((srcPixVal * b16) >> 8);
                    const fga: u8 = @intCast((srcPixVal * a16) >> 8);

                    // break down bgRGBA
                    const bgr: u16 = @intCast(bg.rgba.r);
                    const bgg: u16 = @intCast(bg.rgba.g);
                    const bgb: u16 = @intCast(bg.rgba.b);
                    const bga: u16 = @intCast(bg.rgba.a);

                    // blend
                    const r2: u16 = fgr;
                    const g2: u16 = fgg;
                    const b2: u16 = fgb;
                    const a2: u16 = fga;
                    var r1: u16 = @intCast(bgr);
                    var g1: u16 = @intCast(bgg);
                    var b1: u16 = @intCast(bgb);
                    const a1: u16 = @intCast(bga);

                    r1 = (r1 * (255 - a2) + r2 * a2) / 255;
                    if (r1 > 255) r1 = 255;
                    g1 = (g1 * (255 - a2) + g2 * a2) / 255;
                    if (g1 > 255) g1 = 255;
                    b1 = (b1 * (255 - a2) + b2 * a2) / 255;
                    if (b1 > 255) b1 = 255;

                    _ = c.SDL_SetRenderDrawColor(renderer, @intCast(r1), @intCast(g1), @intCast(b1), @intCast(a1));
                    const ptx = posx + x + dims.off_x;
                    const pty = posy + y + dims.off_y;
//                    if (pty >= HEIGHT - BORDER/2) {
//                        pty = (HEIGHT - BORDER/2) - 1;
//                    }
//                    if (ptx >= WIDTH - BORDER/2) {
//                        ptx = (WIDTH - BORDER/2) - 1;
//                    }
//                    std.debug.assert(ptx >= BORDER/2);
//                    std.debug.assert(pty >= BORDER/2);
//                    std.debug.assert(ptx < WIDTH - BORDER/2);
//                    std.debug.assert(pty < HEIGHT - BORDER/2);
                    _ = c.SDL_RenderPoint(renderer, @floatFromInt(ptx), @floatFromInt(pty));
                }
            }
        }
    }
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
                userevent.type = c.SDL_EVENT_USER;
                userevent.code = 0;
                userevent.data1 = c.NULL;
                userevent.data2 = c.NULL;
                event.type = c.SDL_EVENT_USER;
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

    const gFontSmall = try TrueType.load(@embedFile("pc.ttf"));
    const gFontSmallBold = try TrueType.load(@embedFile("pc-bold.ttf"));

    c.SDL_SetMainReady();

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("SDLZVTerm", WIDTH * SCALE, HEIGHT * SCALE, c.SDL_WINDOW_OPENGL) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, null) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    _ = c.SDL_SetRenderScale(renderer, SCALE, SCALE);

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
        .col = @intCast(COLS),
        .row = @intCast(ROWS),
        .xpixel = 1,
        .ypixel = 1,
    };

    // Set terminal size. Hack to pass 64bit ioctl op as c_int in Darwin
    const IOCSWINSZ:u64 = 0x80087467;
    const TIOCSWINSZ = if (std.Target.Os.Tag.isDarwin(builtin.target.os.tag)) @as(c_int, @truncate(@as(i64, @bitCast(IOCSWINSZ)))) else std.posix.T.IOCSWINSZ;
    const err = std.posix.system.ioctl(master_pt.handle, TIOCSWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.SetTerminalSizeErr;
    }

    _ = c.SDL_StartTextInput(screen);

    var inputThreadData = InputThreadData{
        .file = master_pt,
        .writer = termwriter,
        .quit = false,
    };
    const inputThread = c.SDL_CreateThread(inputThreadFn, "inputThread", @as(*anyopaque, @ptrCast(&inputThreadData)));

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_WaitEvent(&event)) {
            // if inputthread requests a quit, also exit main loop
            if (inputThreadData.quit) {
                quit = true;
                break;
            }
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    quit = true;
                    break;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.mod & c.SDL_KMOD_CTRL > 0) {
                        for (ctrlkeymap) |km| {
                            if (km.keycode == event.key.key) {
                                _ = master_pt.write(km.data) catch {
                                    quit = true;
                                };
                            }
                        }
                    }
                    for (keymap) |km| {
                        if (km.keycode == event.key.key) {
                            _ = master_pt.write(km.data) catch {
                                quit = true;
                            };
                        }
                    }
                },
                c.SDL_EVENT_TEXT_INPUT => {
                    const c_string: [*c]const u8 = event.text.text;
                    _ = try master_pt.write(std.mem.span(c_string));
                },

                else => {},
            }

            if (term.damage) {
                term.damage = false;
                _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
                _ = c.SDL_RenderClear(renderer);

                const cursorPos = term.getCursorPos();

                var y:isize = ROWS-1;
                while(y >= 0) : (y -= 1) {
                    for (0..COLS) |x| {
                        const cell = term.getCell(x, @intCast(y));
                        _ = c.SDL_SetRenderDrawColor(renderer, cell.bg.rgba.r, cell.bg.rgba.g, cell.bg.rgba.b, 0xFF);
                        var rect: c.SDL_FRect = undefined;
                        rect.x = @floatFromInt(x * FONTSIZE / 2 + BORDER/2);
                        rect.y = @floatFromInt(y * FONTSIZE + BORDER/2 + FONTSIZE/4);
                        rect.w = FONTSIZE / 2;
                        rect.h = FONTSIZE;
                        _ = c.SDL_RenderFillRect(renderer, &rect);

                        if (cell.char) |ch| {
                            var font: *const TrueType = &gFontSmall;
                            if (cell.bold) {
                                font = &gFontSmallBold;
                            }

                            try drawString(allocator, renderer, font, &.{ch}, @intCast(BORDER/2 + x * FONTSIZE / 2), @as(i32, @intCast(BORDER/2 + (y+1) * FONTSIZE)), cell.fg, cell.bg);
                        }
                        if (term.cursorvisible and x == cursorPos.x and y == cursorPos.y) {
                            _ = c.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
                            rect.x = @floatFromInt(x * FONTSIZE / 2 + BORDER/2);
                            rect.y = @floatFromInt(y * FONTSIZE + BORDER/2 + FONTSIZE/4);
                            rect.w = FONTSIZE / 2;
                            rect.h = FONTSIZE;
                            _ = c.SDL_RenderFillRect(renderer, &rect);
                        }
                    }
                }

                _ = c.SDL_RenderPresent(renderer);
            }
        }
    }

    // signal inputthread to stop
    inputThreadData.quit = true;
    c.SDL_DetachThread(@constCast(inputThread));
}
