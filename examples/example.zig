// this is the main file which is used by all examples.

const std = @import("std");
const zang = @import("zang");
const common = @import("common.zig");
const c = @import("common/c.zig");
const Parameter = @import("common.zig").Parameter;
const Recorder = @import("recorder.zig").Recorder;
const example = @import(@import("build_options").example);
const visual = @import("visual.zig");

const AUDIO_FORMAT = example.AUDIO_FORMAT;
const AUDIO_SAMPLE_RATE = example.AUDIO_SAMPLE_RATE;
const AUDIO_BUFFER_SIZE = example.AUDIO_BUFFER_SIZE;

const screen_w = 512;
const screen_h = 512;

var g_outputs: [example.MainModule.num_outputs][AUDIO_BUFFER_SIZE]f32 = undefined;
var g_temps: [example.MainModule.num_temps][AUDIO_BUFFER_SIZE]f32 = undefined;

var g_redraw_event: c.Uint32 = undefined;

fn pushRedrawEvent() void {
    var event: c.SDL_Event = undefined;
    event.type = g_redraw_event;
    _ = c.SDL_PushEvent(&event);
}

const UserData = struct {
    main_module: example.MainModule, // only valid if ok is true
    ok: bool,
};

fn audioCallback(
    userdata_: ?*c_void,
    stream_: ?[*]u8,
    len_: c_int,
) callconv(.C) void {
    const userdata = @ptrCast(*UserData, @alignCast(@alignOf(*UserData), userdata_.?));
    const stream = stream_.?[0..@intCast(usize, len_)];

    var outputs: [example.MainModule.num_outputs][]f32 = undefined;
    var temps: [example.MainModule.num_temps][]f32 = undefined;
    var i: usize = undefined;

    const span = zang.Span.init(0, AUDIO_BUFFER_SIZE);

    i = 0;
    while (i < example.MainModule.num_outputs) : (i += 1) {
        outputs[i] = &g_outputs[i];
        zang.zero(span, outputs[i]);
    }
    i = 0;
    while (i < example.MainModule.num_temps) : (i += 1) {
        temps[i] = &g_temps[i];
    }

    if (userdata.ok) {
        userdata.main_module.paint(span, outputs, temps);
    }

    const mul = 0.25;

    switch (example.MainModule.output_audio) {
        .mono => |both| {
            zang.mixDown(stream, outputs[both], AUDIO_FORMAT, 1, 0, mul);
        },
        .stereo => |p| {
            zang.mixDown(stream, outputs[p.left], AUDIO_FORMAT, 2, 0, mul);
            zang.mixDown(stream, outputs[p.right], AUDIO_FORMAT, 2, 1, mul);
        },
    }

    if (@hasDecl(example.MainModule, "output_visualize")) {
        const visualize = outputs[example.MainModule.output_visualize];

        const sync = if (@hasDecl(example.MainModule, "output_sync_oscilloscope"))
            outputs[example.MainModule.output_sync_oscilloscope]
        else
            null;

        if (visuals.newInput(visualize, mul, AUDIO_SAMPLE_RATE, sync)) {
            pushRedrawEvent();
        }
    }
}

const ListenerEvent = enum {
    reload,
};

const Listener = struct {
    socket: std.os.fd_t,

    fn init(port: u16) !Listener {
        // open UDP socket on port 8888
        const socket = try std.os.socket(std.os.AF_INET, std.os.SOCK_DGRAM, std.os.IPPROTO_UDP);
        _ = try std.os.fcntl(socket, std.os.F_SETFL, std.os.O_NONBLOCK);
        var addr: std.os.sockaddr_in = .{
            .port = std.mem.nativeToBig(std.os.in_port_t, port),
            .addr = 0, // INADDR_ANY
        };
        try std.os.bind(socket, @ptrCast(*std.os.sockaddr, &addr), @sizeOf(@TypeOf(addr)));
        std.debug.warn("listening on port {}\n", .{port});
        return Listener{ .socket = socket };
    }

    fn deinit(self: *Listener) void {
        std.os.close(self.socket);
    }

    fn checkForEvent(self: *Listener) !?ListenerEvent {
        var buf: [100]u8 = undefined;

        var from_addr: std.os.sockaddr_in = undefined;
        var from_addr_len: u32 = @sizeOf(@TypeOf(from_addr));

        const num_bytes = std.os.recvfrom(self.socket, &buf, buf.len, @ptrCast(*std.os.sockaddr, &from_addr), &from_addr_len) catch |err| {
            if (err == error.WouldBlock) {
                return null;
            } else {
                return err;
            }
        };

        if (num_bytes > 0) {
            const string = &buf;

            if (std.mem.eql(u8, string, "reload")) {
                return ListenerEvent.reload;
            }
        }

        return null;
    }
};

var visuals: visual.Visuals = undefined;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    visuals = try visual.Visuals.init(allocator, screen_w, screen_h);
    defer visuals.deinit();

    var filename: []const u8 = "";
    var userdata: UserData = .{
        .ok = true,
        .main_module = undefined,
    };
    if (@typeInfo(@typeInfo(@TypeOf(example.MainModule.init)).Fn.return_type.?) == .ErrorUnion) {
        // note: arg values are never freed... oh well
        var args = std.process.args();
        _ = args.next(allocator); // skip program name
        filename = try args.next(allocator) orelse return error.MissingArgument;

        var script_error: ?[]const u8 = null;
        userdata.main_module = example.MainModule.init(filename, &script_error) catch blk: {
            visuals.setScriptError(script_error);
            visuals.setState(visuals.state);
            userdata.ok = false;
            break :blk undefined;
        };
    } else {
        userdata.main_module = example.MainModule.init();
    }
    defer if (userdata.ok) {
        if (@hasDecl(example.MainModule, "deinit")) {
            userdata.main_module.deinit();
        }
    };

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    errdefer c.SDL_Quit();

    g_redraw_event = c.SDL_RegisterEvents(1);

    const SDL_WINDOWPOS_UNDEFINED = @bitCast(c_int, c.SDL_WINDOWPOS_UNDEFINED_MASK);
    const window = c.SDL_CreateWindow(
        "zang",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        screen_w,
        screen_h,
        0,
    ) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    errdefer c.SDL_DestroyWindow(window);

    const screen = @ptrCast(*c.SDL_Surface, c.SDL_GetWindowSurface(window) orelse {
        c.SDL_Log("Unable to get window surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    });

    var want: c.SDL_AudioSpec = undefined;
    want.freq = AUDIO_SAMPLE_RATE;
    want.format = switch (AUDIO_FORMAT) {
        .signed8 => c.AUDIO_S8,
        .signed16_lsb => c.AUDIO_S16LSB,
    };
    want.channels = switch (example.MainModule.output_audio) {
        .mono => 1,
        .stereo => 2,
    };
    want.samples = AUDIO_BUFFER_SIZE;
    want.callback = audioCallback;
    want.userdata = &userdata;

    const device: c.SDL_AudioDeviceID = c.SDL_OpenAudioDevice(
        0, // device name (NULL)
        0, // non-zero to open for recording instead of playback
        &want, // desired output format
        0, // obtained output format (NULL)
        0, // allowed changes: 0 means `obtained` will not differ from `want`,
        // and SDL will do any necessary resampling behind the scenes
    );
    if (device == 0) {
        c.SDL_Log("Failed to open audio: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    errdefer c.SDL_CloseAudio();

    var maybe_listener: ?Listener = null;
    if (std.process.getEnvVarOwned(allocator, "ZANG_LISTEN_PORT") catch null) |port_str| {
        const maybe_port = std.fmt.parseInt(u16, port_str, 10) catch blk: {
            std.debug.warn("invalid value for ZANG_LISTEN_PORT\n", .{});
            break :blk null;
        };
        allocator.free(port_str);
        if (maybe_port) |port| {
            maybe_listener = Listener.init(port) catch |err| blk: {
                std.debug.warn("Listener.init failed: {}\n", .{err});
                break :blk null;
            };
        }
    }

    // this seems to match the value of SDL_GetTicks the first time the audio
    // callback is called
    const start_time = @intToFloat(f32, c.SDL_GetTicks()) / 1000.0;

    c.SDL_PauseAudioDevice(device, 0); // unpause

    pushRedrawEvent();

    var sel_param_index: usize = 0;
    var param_dirty_counter: u32 = 0;
    var recorder = Recorder.init();

    var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp()));

    var event: c.SDL_Event = undefined;

    var quit = false;
    while (!quit) {
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                    break;
                },
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const down = event.type == c.SDL_KEYDOWN;
                    if (event.key.keysym.sym == c.SDLK_ESCAPE and down) {
                        quit = true;
                        break;
                    }
                    if (event.key.keysym.sym == c.SDLK_F1 and down) {
                        c.SDL_LockAudioDevice(device);

                        visuals.setState(.help);
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (event.key.keysym.sym == c.SDLK_F2 and down) {
                        c.SDL_LockAudioDevice(device);

                        visuals.setState(.main);
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (event.key.keysym.sym == c.SDLK_F3 and down) {
                        c.SDL_LockAudioDevice(device);

                        visuals.setState(.oscil);
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (event.key.keysym.sym == c.SDLK_F4 and down) {
                        c.SDL_LockAudioDevice(device);

                        visuals.setState(.full_fft);
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (event.key.keysym.sym == c.SDLK_F5 and down) {
                        c.SDL_LockAudioDevice(device);

                        visuals.setState(.params);
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (event.key.keysym.sym == c.SDLK_F6 and down) {
                        c.SDL_LockAudioDevice(device);

                        visuals.toggleLogarithmicFFT();
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (@hasField(example.MainModule, "parameters") and
                        userdata.main_module.parameters.len > 0)
                    {
                        if (event.key.keysym.sym == c.SDLK_UP and down) {
                            if (sel_param_index > 0) {
                                sel_param_index -= 1;
                            } else {
                                sel_param_index = userdata.main_module.parameters.len - 1;
                            }
                            param_dirty_counter +%= 1;
                            pushRedrawEvent();
                        }
                        if (event.key.keysym.sym == c.SDLK_DOWN and down) {
                            if (sel_param_index < userdata.main_module.parameters.len - 1) {
                                sel_param_index += 1;
                            } else {
                                sel_param_index = 0;
                            }
                            param_dirty_counter +%= 1;
                            pushRedrawEvent();
                        }
                        if (event.key.keysym.sym == c.SDLK_LEFT and down) {
                            c.SDL_LockAudioDevice(device);

                            const param = &userdata.main_module.parameters[sel_param_index];
                            if (param.current_value > 0) {
                                param.current_value -= 1;
                            } else {
                                param.current_value = param.num_values - 1;
                            }
                            param_dirty_counter +%= 1;
                            pushRedrawEvent();

                            c.SDL_UnlockAudioDevice(device);
                        }
                        if (event.key.keysym.sym == c.SDLK_RIGHT and down) {
                            c.SDL_LockAudioDevice(device);

                            const param = &userdata.main_module.parameters[sel_param_index];
                            if (param.current_value < param.num_values - 1) {
                                param.current_value += 1;
                            } else {
                                param.current_value = 0;
                            }
                            param_dirty_counter +%= 1;
                            pushRedrawEvent();

                            c.SDL_UnlockAudioDevice(device);
                        }
                        if (event.key.keysym.sym == c.SDLK_BACKSPACE and down) {
                            // randomize all parameters
                            c.SDL_LockAudioDevice(device);

                            for (userdata.main_module.parameters) |*param, ii| {
                                if (param.favor_low_values) {
                                    var f = prng.random.float(f32);
                                    f = std.math.pow(f32, f, 3.0);
                                    f *= @intToFloat(f32, param.num_values);
                                    param.current_value = @floatToInt(u32, f);
                                } else {
                                    param.current_value = prng.random.uintLessThan(u32, param.num_values);
                                }
                            }
                            param_dirty_counter +%= 1;
                            pushRedrawEvent();

                            c.SDL_UnlockAudioDevice(device);
                        }
                    }
                    if (event.key.keysym.sym == c.SDLK_BACKQUOTE and down and event.key.repeat == 0) {
                        c.SDL_LockAudioDevice(device);

                        recorder.cycleMode();
                        pushRedrawEvent();

                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (event.key.keysym.sym == c.SDLK_RETURN and down) {
                        c.SDL_LockAudioDevice(device);
                        if (userdata.ok) {
                            if (@hasDecl(example.MainModule, "deinit")) {
                                userdata.main_module.deinit();
                            }
                        }
                        visuals.setScriptError(null);
                        visuals.setState(visuals.state);
                        userdata.ok = true;
                        if (@typeInfo(@typeInfo(@TypeOf(example.MainModule.init)).Fn.return_type.?) == .ErrorUnion) {
                            var script_error: ?[]const u8 = null;
                            userdata.main_module = example.MainModule.init(filename, &script_error) catch blk: {
                                visuals.setScriptError(script_error);
                                visuals.setState(visuals.state);
                                userdata.ok = false;
                                break :blk undefined;
                            };
                        } else {
                            userdata.main_module = example.MainModule.init();
                        }
                        c.SDL_UnlockAudioDevice(device);
                    }
                    if (@hasDecl(example.MainModule, "keyEvent")) {
                        if (event.key.repeat == 0) {
                            c.SDL_LockAudioDevice(device);
                            if (userdata.ok) {
                                //const impulse_frame = getImpulseFrame(
                                //    AUDIO_BUFFER_SIZE,
                                //    AUDIO_SAMPLE_RATE,
                                //    start_time,
                                //);
                                const impulse_frame = getImpulseFrame();
                                if (userdata.main_module.keyEvent(event.key.keysym.sym, down, impulse_frame)) {
                                    recorder.recordEvent(event.key.keysym.sym, down);
                                    recorder.trackEvent(event.key.keysym.sym, down);
                                }
                            }
                            c.SDL_UnlockAudioDevice(device);
                        }
                    }
                },
                c.SDL_MOUSEMOTION => {
                    if (@hasDecl(example.MainModule, "mouseEvent")) {
                        const x = @intToFloat(f32, event.motion.x) /
                            @intToFloat(f32, screen_w - 1);
                        const y = @intToFloat(f32, event.motion.y) /
                            @intToFloat(f32, screen_h - 1);
                        const impulse_frame = getImpulseFrame();

                        c.SDL_LockAudioDevice(device);
                        userdata.main_module.mouseEvent(x, y, impulse_frame);
                        c.SDL_UnlockAudioDevice(device);
                    }
                },
                else => {},
            }

            if (event.type == g_redraw_event) {
                c.SDL_LockAudioDevice(device);

                _ = c.SDL_LockSurface(screen);

                const pitch = @intCast(usize, screen.pitch) >> 2;
                const pixels = @ptrCast([*]u32, @alignCast(@alignOf(u32), screen.pixels))[0 .. screen_h * pitch];

                const vis_screen: visual.Screen = .{
                    .width = screen_w,
                    .height = screen_h,
                    .pixels = pixels,
                    .pitch = pitch,
                };

                visuals.blit(vis_screen, .{
                    .recorder_state = recorder.state,
                    .parameters = if (@hasField(example.MainModule, "parameters"))
                        &userdata.main_module.parameters
                    else
                        &[0]Parameter{},
                    .sel_param_index = sel_param_index,
                    .param_dirty_counter = param_dirty_counter,
                });

                c.SDL_UnlockSurface(screen);
                _ = c.SDL_UpdateWindowSurface(window);

                c.SDL_UnlockAudioDevice(device);
            }
        }

        while (recorder.getNote()) |n| {
            if (@hasDecl(example.MainModule, "keyEvent")) {
                c.SDL_LockAudioDevice(device);
                if (userdata.ok) {
                    const impulse_frame = 0;
                    if (userdata.main_module.keyEvent(n.key, n.down, impulse_frame)) {
                        recorder.trackEvent(n.key, n.down);
                    }
                }
                c.SDL_UnlockAudioDevice(device);
            }
        }

        if (maybe_listener) |*listener| {
            const maybe_event = listener.checkForEvent() catch |err| blk: {
                std.debug.warn("listener.checkForEvent failed: {}\n", .{err});
                listener.deinit();
                maybe_listener = null;
                break :blk null;
            };

            if (maybe_event) |listener_event| {
                switch (listener_event) {
                    .reload => {
                        c.SDL_LockAudioDevice(device);
                        if (userdata.ok) {
                            if (@hasDecl(example.MainModule, "deinit")) {
                                userdata.main_module.deinit();
                            }
                        }
                        visuals.setScriptError(null);
                        visuals.setState(visuals.state);
                        userdata.ok = true;
                        if (@typeInfo(@typeInfo(@TypeOf(example.MainModule.init)).Fn.return_type.?) == .ErrorUnion) {
                            var script_error: ?[]const u8 = null;
                            userdata.main_module = example.MainModule.init(filename, &script_error) catch blk: {
                                visuals.setScriptError(script_error);
                                visuals.setState(visuals.state);
                                userdata.ok = false;
                                break :blk undefined;
                            };
                        } else {
                            userdata.main_module = example.MainModule.init();
                        }
                        c.SDL_UnlockAudioDevice(device);
                    },
                }
            }
        }

        // TODO is there a way to delay 10ms or until a new event arrives, whichever comes first?
        c.SDL_Delay(15);
    }

    if (maybe_listener) |*listener| {
        listener.deinit();
    }
    c.SDL_LockAudioDevice(device);
    c.SDL_UnlockAudioDevice(device);
    c.SDL_CloseAudioDevice(device);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

// start notes at a random time within the mix buffer.
// this is only for testing purposes, because if i start everything at 0 there
// are some code paths not being hit.
// TODO - actually time the proper impulse frame
//var r = std.rand.DefaultPrng.init(0);

fn getImpulseFrame() usize {
    // FIXME - i was using random values as a kind of test, but this is
    // actually bad. it means if you press two keys at the same time, they get
    // different values, and the second might have an earlier value than the
    // first, which will cause it to get discarded by the ImpulseQueue!
    //return r.random.intRangeLessThan(usize, 0, example.AUDIO_BUFFER_SIZE);
    return 0;
}

//// come up with a frame index to start the sound at
//fn getImpulseFrame(
//    buffer_size: usize,
//    sample_rate: usize,
//    start_time: f32,
//    current_frame_index: usize,
//) usize {
//    // `current_frame_index` is the END of the mix frame currently queued to
//    // be heard next
//    const one_mix_frame = @intToFloat(f32, buffer_size) /
//        @intToFloat(f32, sample_rate);
//
//    // time of the start of the mix frame currently underway
//    const mix_end = @intToFloat(f32, current_frame_index) /
//        @intToFloat(f32, sample_rate);
//    const mix_start = mix_end - one_mix_frame;
//
//    const current_time =
//        @intToFloat(f32, c.SDL_GetTicks()) / 1000.0 - start_time;
//
//    // if everything is working properly, current_time should be
//    // between mix_start and mix_end. there might be a little bit of an
//    // offset but i'm not going to deal with that for now.
//
//    // i just need to make sure that if this code queues up an impulse
//    // that's in the "past" when it actually gets picked up by the
//    // audio thread, it will still be picked up (somehow)!
//
//    // FIXME - shouldn't be multiplied by 2! this is only to
//    // compensate for the clocks sometimes starting out of sync
//    const impulse_time = current_time + one_mix_frame * 2.0;
//    const impulse_frame =
//        @floatToInt(usize, impulse_time * @intToFloat(f32, sample_rate));
//
//    return impulse_frame;
//}
