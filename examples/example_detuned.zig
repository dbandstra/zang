const std = @import("std");
const zang = @import("zang");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");
const StereoEchoes = @import("modules.zig").StereoEchoes(15000);

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_detuned
    \\
    \\Play an instrument with the keyboard. There is a
    \\random warble added to the note frequencies, which was
    \\created using white noise and a low-pass filter.
    \\
    \\Press spacebar to cycle through a few modes:
    \\
    \\  1. wide warble, no echo
    \\  2. narrow warble, no echo
    \\  3. wide warble, echo
    \\  4. narrow warble, echo (here the warble does a good
    \\     job of avoiding constructive interference from
    \\     the echo)
;

const a4 = 440.0;

pub const Instrument = struct {
    pub const num_outputs = 2;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        freq_warble: []const f32,
        note_on: bool,
    };

    osc: mod.TriSawOsc,
    env: mod.Envelope,
    main_filter: mod.Filter,

    pub fn init() Instrument {
        return .{
            .osc = mod.TriSawOsc.init(),
            .env = mod.Envelope.init(),
            .main_filter = mod.Filter.init(),
        };
    }

    pub fn paint(
        self: *Instrument,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        var i: usize = span.start;
        while (i < span.end) : (i += 1) {
            temps[0][i] = params.freq *
                std.math.pow(f32, 2.0, params.freq_warble[i]);
        }
        // paint with oscillator into temps[1]
        zang.zero(span, temps[1]);
        self.osc.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[0]),
            .color = 0.0,
        });
        // output frequency for syncing oscilloscope
        zang.addInto(span, outputs[1], temps[0]);
        // slight volume reduction
        zang.multiplyWithScalar(span, temps[1], 0.75);
        // combine with envelope
        zang.zero(span, temps[0]);
        self.env.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 0.025 },
            .decay = .{ .cubed = 0.1 },
            .release = .{ .cubed = 1.0 },
            .sustain_volume = 0.5,
            .note_on = params.note_on,
        });
        zang.zero(span, temps[2]);
        zang.multiply(span, temps[2], temps[1], temps[0]);
        // add main filter
        self.main_filter.paint(span, .{outputs[0]}, .{}, note_id_changed, .{
            .input = temps[2],
            .type = .low_pass,
            .cutoff = zang.constant(mod.Filter.cutoffFromFrequency(
                //params.freq + 400.0,
                880.0,
                params.sample_rate,
            )),
            .res = 0.8,
        });
    }
};

pub const OuterInstrument = struct {
    pub const num_outputs = 2;
    pub const num_temps = 4;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
        mode: u32,
    };

    noise: mod.Noise,
    noise_filter: mod.Filter,
    inner: Instrument,

    pub fn init() OuterInstrument {
        return .{
            .noise = mod.Noise.init(),
            .noise_filter = mod.Filter.init(),
            .inner = Instrument.init(),
        };
    }

    pub fn paint(
        self: *OuterInstrument,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        // temps[0] = filtered noise
        // note: filter frequency is set to 4hz. i wanted to go slower but
        // unfortunately at below 4, the filter degrades and the output
        // frequency slowly sinks to zero
        // (the number is relative to sample rate, so at 96khz it should be at
        // least 8hz)
        zang.zero(span, temps[1]);
        self.noise.paint(span, .{temps[1]}, .{}, note_id_changed, .{ .color = .white });
        zang.zero(span, temps[0]);
        self.noise_filter.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .input = temps[1],
            .type = .low_pass,
            .cutoff = zang.constant(mod.Filter.cutoffFromFrequency(
                4.0,
                params.sample_rate,
            )),
            .res = 0.0,
        });

        if ((params.mode & 1) == 0) {
            zang.multiplyWithScalar(span, temps[0], 4.0);
        }

        self.inner.paint(
            span,
            outputs,
            .{ temps[1], temps[2], temps[3] },
            note_id_changed,
            .{
                .sample_rate = params.sample_rate,
                .freq = params.freq,
                .freq_warble = temps[0],
                .note_on = params.note_on,
            },
        );
    }
};

pub const MainModule = struct {
    pub const num_outputs = 3;
    pub const num_temps = 5;

    pub const output_audio = common.AudioOut{ .stereo = .{ .left = 0, .right = 1 } };
    pub const output_visualize = 0;
    pub const output_sync_oscilloscope = 2;

    key: ?i32,
    iq: zang.Notes(OuterInstrument.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    outer: OuterInstrument,
    trigger: zang.Trigger(OuterInstrument.Params),
    echoes: StereoEchoes,
    mode: u32,

    pub fn init() MainModule {
        return .{
            .key = null,
            .iq = zang.Notes(OuterInstrument.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .outer = OuterInstrument.init(),
            .trigger = zang.Trigger(OuterInstrument.Params).init(),
            .echoes = StereoEchoes.init(),
            .mode = 0,
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        // FIXME - here's something missing in the API... what if i want to
        // pass some "global" params to paintFromImpulses? in other words,
        // saw that of the fields in OuterInstrument.Params, i only want to set
        // some of them in the impulse queue. others i just want to pass once,
        // here. for example i would pass the "mode" field.
        // FIXME - is the above comment obsolete?
        zang.zero(span, temps[0]);
        {
            var ctr = self.trigger.counter(span, self.iq.consume());
            while (self.trigger.next(&ctr)) |result| {
                self.outer.paint(
                    result.span,
                    .{ temps[0], outputs[2] },
                    .{ temps[1], temps[2], temps[3], temps[4] },
                    result.note_id_changed,
                    result.params,
                );
            }
        }

        if ((self.mode & 2) == 0) {
            // avoid the echo effect
            zang.addInto(span, outputs[0], temps[0]);
            zang.addInto(span, outputs[1], temps[0]);
            zang.zero(span, temps[0]);
        }

        self.echoes.paint(
            span,
            .{ outputs[0], outputs[1] },
            .{ temps[1], temps[2], temps[3], temps[4] },
            false,
            .{
                .input = temps[0],
                .feedback_volume = 0.6,
                .cutoff = 0.1,
            },
        );
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (key == c.SDLK_SPACE and down) {
            self.mode = (self.mode + 1) & 3;
            return false;
        }
        if (common.getKeyRelFreq(key)) |rel_freq| {
            if (down or (if (self.key) |nh| nh == key else false)) {
                self.key = if (down) key else null;
                self.iq.push(impulse_frame, self.idgen.nextId(), .{
                    .sample_rate = AUDIO_SAMPLE_RATE,
                    .freq = a4 * rel_freq * 0.5,
                    .note_on = down,
                    // note: because i'm passing mode here, a change to mode
                    // take effect until you press a new key
                    .mode = self.mode,
                });
            }
            return true;
        }
        return false;
    }
};
