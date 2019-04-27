// in this example you can trigger a laser sound effect by hitting the space bar.
// there are some alternate sound effects on the a, s, and d keys

const std = @import("std");
const zang = @import("zang");
const common = @import("common.zig");
const c = @import("common/sdl.zig");

pub const AUDIO_FORMAT = zang.AudioFormat.S16LSB;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;
pub const AUDIO_CHANNELS = 1;

pub const MyNoteParams = LaserPlayer.Params;
pub const MyNotes = zang.Notes(MyNoteParams);

const LaserPlayer = struct {
    pub const NumOutputs = 1;
    pub const NumInputs = 0;
    pub const NumTemps = 3;
    pub const Params = struct {
        freq: f32, // TODO rename to freq_mul
        carrier_mul: f32,
        modulator_mul: f32,
        modulator_rad: f32,
    };

    carrier_curve: zang.Curve,
    carrier: zang.Oscillator,
    modulator_curve: zang.Curve,
    modulator: zang.Oscillator,
    volume_curve: zang.Curve,

    fn init() LaserPlayer {
        const A = 1000.0;
        const B = 200.0;
        const C = 100.0;

        return LaserPlayer {
            .carrier_curve = zang.Curve.init(.SmoothStep, []zang.CurveNode {
                zang.CurveNode{ .t = 0.0, .value = A },
                zang.CurveNode{ .t = 0.1, .value = B },
                zang.CurveNode{ .t = 0.2, .value = C },
            }),
            .carrier = zang.Oscillator.init(.Sine),
            .modulator_curve = zang.Curve.init(.SmoothStep, []zang.CurveNode {
                zang.CurveNode{ .t = 0.0, .value = A },
                zang.CurveNode{ .t = 0.1, .value = B },
                zang.CurveNode{ .t = 0.2, .value = C },
            }),
            .modulator = zang.Oscillator.init(.Sine),
            .volume_curve = zang.Curve.init(.SmoothStep, []zang.CurveNode {
                zang.CurveNode{ .t = 0.0, .value = 0.0 },
                zang.CurveNode{ .t = 0.004, .value = 1.0 },
                zang.CurveNode{ .t = 0.2, .value = 0.0 },
            }),
        };
    }

    fn reset(self: *LaserPlayer) void {
        self.carrier_curve.reset();
        self.modulator_curve.reset();
        self.volume_curve.reset();
    }

    fn paintSpan(self: *LaserPlayer, sample_rate: f32, outputs: [NumOutputs][]f32, inputs: [NumInputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        const out = outputs[0];

        zang.zero(temps[0]);
        self.modulator_curve.paintSpan(sample_rate, [1][]f32{temps[0]}, [0][]f32{}, [0][]f32{}, zang.Curve.Params {
            .freq_mul = params.freq * params.modulator_mul,
        });
        zang.zero(temps[1]);
        self.modulator.paintControlledFrequency(sample_rate, temps[1], temps[0]);
        zang.multiplyWithScalar(temps[1], params.modulator_rad);
        zang.zero(temps[0]);
        self.carrier_curve.paintSpan(sample_rate, [1][]f32{temps[0]}, [0][]f32{}, [0][]f32{}, zang.Curve.Params {
            .freq_mul = params.freq * params.carrier_mul,
        });
        zang.zero(temps[2]);
        self.carrier.paintControlledPhaseAndFrequency(sample_rate, temps[2], temps[1], temps[0]);
        zang.zero(temps[0]);
        self.volume_curve.paintSpan(sample_rate, [1][]f32{temps[0]}, [0][]f32{}, [0][]f32{}, zang.Curve.Params {
            .freq_mul = 1.0,
        });
        zang.multiply(out, temps[0], temps[2]);
    }
};

var g_buffers: struct {
    buf0: [AUDIO_BUFFER_SIZE]f32,
    buf1: [AUDIO_BUFFER_SIZE]f32,
    buf2: [AUDIO_BUFFER_SIZE]f32,
    buf3: [AUDIO_BUFFER_SIZE]f32,
} = undefined;

pub const MainModule = struct {
    iq: MyNotes.ImpulseQueue,
    laser_player: zang.Triggerable(LaserPlayer),

    r: std.rand.Xoroshiro128,

    pub fn init() MainModule {
        return MainModule{
            .iq = MyNotes.ImpulseQueue.init(),
            .laser_player = zang.initTriggerable(LaserPlayer.init()),
            .r = std.rand.DefaultPrng.init(0),
        };
    }

    pub fn paint(self: *MainModule, sample_rate: f32) [AUDIO_CHANNELS][]const f32 {
        const out = g_buffers.buf0[0..];
        const tmp0 = g_buffers.buf1[0..];
        const tmp1 = g_buffers.buf2[0..];
        const tmp2 = g_buffers.buf3[0..];

        zang.zero(out);

        self.laser_player.paintFromImpulses(sample_rate, [1][]f32{out}, [0][]f32{}, [3][]f32{tmp0, tmp1, tmp2}, self.iq.consume());

        return [AUDIO_CHANNELS][]const f32 {
            out,
        };
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, out_iq: **MyNotes.ImpulseQueue, out_params: *MyNoteParams) bool {
        if (down) {
            const base_freq = 1.0;
            const variance = 0.3;

            out_iq.* = &self.iq;
            out_params.* = MyNoteParams {
                .freq = base_freq + self.r.random.float(f32) * variance - 0.5 * variance,
                .carrier_mul = undefined,
                .modulator_mul = undefined,
                .modulator_rad = undefined,
            };

            switch (key) {
                c.SDLK_SPACE => {
                    // player laser
                    const carrier_mul_variance = 0.0;
                    const modulator_mul_variance = 0.1;
                    const modulator_rad_variance = 0.25;
                    out_params.carrier_mul = 2.0 + self.r.random.float(f32) * carrier_mul_variance - 0.5 * carrier_mul_variance;
                    out_params.modulator_mul = 0.5 + self.r.random.float(f32) * modulator_mul_variance - 0.5 * modulator_mul_variance;
                    out_params.modulator_rad = 0.5 + self.r.random.float(f32) * modulator_rad_variance - 0.5 * modulator_rad_variance;
                    return true;
                },
                c.SDLK_a => {
                    // enemy laser
                    out_params.carrier_mul = 4.0;
                    out_params.modulator_mul = 0.125;
                    out_params.modulator_rad = 1.0;
                    return true;
                },
                c.SDLK_s => {
                    // pain sound?
                    out_params.carrier_mul = 0.5;
                    out_params.modulator_mul = 0.125;
                    out_params.modulator_rad = 1.0;
                    return true;
                },
                c.SDLK_d => {
                    // some web effect?
                    out_params.carrier_mul = 1.0;
                    out_params.modulator_mul = 9.0;
                    out_params.modulator_rad = 1.0;
                    return true;
                },
                else => {},
            }
        }

        return false;
    }
};
