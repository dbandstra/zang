const zang = @import("zang");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_stereo
    \\
    \\A wind-like noise effect slowly oscillates between the
    \\left and right speakers.
    \\
    \\This example is not interactive.
;

// take input (-1 to +1) and scale it to (min to max)
fn scaleWave(
    span: zang.Span,
    out: []f32,
    in: []const f32,
    tmp0: []f32,
    min: f32,
    max: f32,
) void {
    zang.zero(span, tmp0);
    zang.multiplyScalar(span, tmp0, in, (max - min) * 0.5);
    zang.addScalar(span, out, tmp0, (max - min) * 0.5 + min);
}

// overwrite out with (1 - out)
fn invertWaveInPlace(span: zang.Span, out: []f32, tmp0: []f32) void {
    zang.zero(span, tmp0);
    zang.multiplyScalar(span, tmp0, out, -1.0);
    zang.zero(span, out);
    zang.addScalar(span, out, tmp0, 1.0);
}

const NoiseModule = struct {
    pub const num_outputs = 2;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        pan: []const f32,
        min: f32,
        max: f32,
        cutoff_frequency: f32,
    };

    noise: mod.Noise,
    flt: mod.Filter,

    fn init() NoiseModule {
        return .{
            .noise = mod.Noise.init(),
            .flt = mod.Filter.init(),
        };
    }

    fn paint(
        self: *NoiseModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        // temps[0] = filtered noise
        zang.zero(span, temps[0]);
        zang.zero(span, temps[1]);
        self.noise.paint(span, .{temps[1]}, .{}, note_id_changed, .{ .color = .white });
        self.flt.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .input = temps[1],
            .type = .low_pass,
            .cutoff = zang.constant(mod.Filter.cutoffFromFrequency(
                params.cutoff_frequency,
                params.sample_rate,
            )),
            .res = 0.4,
        });

        // increase volume
        zang.multiplyWithScalar(span, temps[0], 4.0);

        // temps[1] = pan scaled to (min to max)
        zang.zero(span, temps[1]);
        scaleWave(span, temps[1], params.pan, temps[2], params.min, params.max);

        // left channel += temps[0] * temps[1]
        zang.multiply(span, outputs[0], temps[0], temps[1]);

        // temps[1] = 1 - temps[1]
        invertWaveInPlace(span, temps[1], temps[2]);

        // right channel += temps[0] * temps[1]
        zang.multiply(span, outputs[1], temps[0], temps[1]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 2;
    pub const num_temps = 4;

    pub const output_audio = common.AudioOut{ .stereo = .{ .left = 0, .right = 1 } };
    pub const output_visualize = 0;

    osc: mod.SineOsc,
    noisem0: NoiseModule,
    noisem1: NoiseModule,

    pub fn init() MainModule {
        return .{
            .osc = mod.SineOsc.init(),
            .noisem0 = NoiseModule.init(),
            .noisem1 = NoiseModule.init(),
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        const sample_rate = AUDIO_SAMPLE_RATE;

        // temps[0] = slow oscillator representing left/right pan (-1 to +1)
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{}, false, .{
            .sample_rate = sample_rate,
            .freq = zang.constant(0.1),
            .phase = zang.constant(0.0),
        });

        // paint two noise voices
        self.noisem0.paint(span, outputs, .{ temps[1], temps[2], temps[3] }, false, .{
            .sample_rate = sample_rate,
            .pan = temps[0],
            .min = 0.0,
            .max = 0.5,
            .cutoff_frequency = 320.0,
        });
        self.noisem1.paint(span, outputs, .{ temps[1], temps[2], temps[3] }, false, .{
            .sample_rate = sample_rate,
            .pan = temps[0],
            .min = 0.5,
            .max = 1.0,
            .cutoff_frequency = 380.0,
        });
    }
};
