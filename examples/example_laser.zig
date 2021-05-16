const std = @import("std");
const zang = @import("zang");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_laser
    \\
    \\Trigger a "laser" sound effect by pressing the
    \\spacebar. Some parameters of the sound are randomly
    \\perturbed.
    \\
    \\Press "a", "s", or "d" for some alternate sound
    \\effects based on the same module.
;

const carrier_curve = [_]mod.Curve.Node{
    .{ .t = 0.0, .value = 1000.0 },
    .{ .t = 0.1, .value = 200.0 },
    .{ .t = 0.2, .value = 100.0 },
};

const modulator_curve = [_]mod.Curve.Node{
    .{ .t = 0.0, .value = 1000.0 },
    .{ .t = 0.1, .value = 200.0 },
    .{ .t = 0.2, .value = 100.0 },
};

const volume_curve = [_]mod.Curve.Node{
    .{ .t = 0.0, .value = 0.0 },
    .{ .t = 0.004, .value = 1.0 },
    .{ .t = 0.2, .value = 0.0 },
};

const LaserPlayer = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        freq_mul: f32,
        carrier_mul: f32,
        modulator_mul: f32,
        modulator_rad: f32,
    };

    carrier_curve: mod.Curve,
    carrier: mod.SineOsc,
    modulator_curve: mod.Curve,
    modulator: mod.SineOsc,
    volume_curve: mod.Curve,

    fn init() LaserPlayer {
        return .{
            .carrier_curve = mod.Curve.init(),
            .carrier = mod.SineOsc.init(),
            .modulator_curve = mod.Curve.init(),
            .modulator = mod.SineOsc.init(),
            .volume_curve = mod.Curve.init(),
        };
    }

    fn paint(
        self: *LaserPlayer,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        const out = outputs[0];

        zang.zero(span, temps[0]);
        self.modulator_curve.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .function = .smoothstep,
            .curve = &modulator_curve,
        });
        zang.multiplyWithScalar(span, temps[0], params.freq_mul * params.modulator_mul);

        zang.zero(span, temps[1]);
        self.modulator.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[0]),
            .phase = zang.constant(0.0),
        });
        zang.multiplyWithScalar(span, temps[1], params.modulator_rad);

        zang.zero(span, temps[0]);
        self.carrier_curve.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .function = .smoothstep,
            .curve = &carrier_curve,
        });
        zang.multiplyWithScalar(span, temps[0], params.freq_mul * params.carrier_mul);

        zang.zero(span, temps[2]);
        self.carrier.paint(span, .{temps[2]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[0]),
            .phase = zang.buffer(temps[1]),
        });

        zang.zero(span, temps[0]);
        self.volume_curve.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .function = .smoothstep,
            .curve = &volume_curve,
        });

        zang.multiply(span, out, temps[0], temps[2]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    iq: zang.Notes(LaserPlayer.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    player: LaserPlayer,
    trigger: zang.Trigger(LaserPlayer.Params),

    r: std.rand.Xoroshiro128,

    pub fn init() MainModule {
        return .{
            .iq = zang.Notes(LaserPlayer.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .player = LaserPlayer.init(),
            .trigger = zang.Trigger(LaserPlayer.Params).init(),
            .r = std.rand.DefaultPrng.init(0),
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        var ctr = self.trigger.counter(span, self.iq.consume());
        while (self.trigger.next(&ctr)) |result| {
            self.player.paint(
                result.span,
                outputs,
                temps,
                result.note_id_changed,
                result.params,
            );
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (down) {
            const variance = 0.3;
            const freq_mul = 1.0 + self.r.random.float(f32) * variance -
                0.5 * variance;

            switch (key) {
                c.SDLK_SPACE => {
                    // player laser
                    const carrier_mul_variance = 0.0;
                    const modulator_mul_variance = 0.1;
                    const modulator_rad_variance = 0.25;
                    self.iq.push(impulse_frame, self.idgen.nextId(), .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .freq_mul = freq_mul,
                        .carrier_mul = 2.0 +
                            self.r.random.float(f32) * carrier_mul_variance -
                            0.5 * carrier_mul_variance,
                        .modulator_mul = 0.5 +
                            self.r.random.float(f32) * modulator_mul_variance -
                            0.5 * modulator_mul_variance,
                        .modulator_rad = 0.5 +
                            self.r.random.float(f32) * modulator_rad_variance -
                            0.5 * modulator_rad_variance,
                    });
                },
                c.SDLK_a => {
                    // enemy laser
                    self.iq.push(impulse_frame, self.idgen.nextId(), .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .freq_mul = freq_mul,
                        .carrier_mul = 4.0,
                        .modulator_mul = 0.125,
                        .modulator_rad = 1.0,
                    });
                },
                c.SDLK_s => {
                    // pain sound?
                    self.iq.push(impulse_frame, self.idgen.nextId(), .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .freq_mul = freq_mul,
                        .carrier_mul = 0.5,
                        .modulator_mul = 0.125,
                        .modulator_rad = 1.0,
                    });
                },
                c.SDLK_d => {
                    // some web effect?
                    self.iq.push(impulse_frame, self.idgen.nextId(), .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .freq_mul = freq_mul,
                        .carrier_mul = 1.0,
                        .modulator_mul = 9.0,
                        .modulator_rad = 1.0,
                    });
                },
                else => return false,
            }
            return true;
        }
        return false;
    }
};
