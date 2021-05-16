const zang = @import("zang");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_curve
    \\
    \\Trigger a weird sound effect with the keyboard. The
    \\sound is defined using a curve, and scales with the
    \\frequency of the key you press.
;

const carrier_curve = [_]zang.CurveNode{
    .{ .t = 0.0, .value = 440.0 },
    .{ .t = 0.5, .value = 880.0 },
    .{ .t = 1.0, .value = 110.0 },
    .{ .t = 1.5, .value = 660.0 },
    .{ .t = 2.0, .value = 330.0 },
    .{ .t = 3.9, .value = 20.0 },
};

const modulator_curve = [_]zang.CurveNode{
    .{ .t = 0.0, .value = 110.0 },
    .{ .t = 1.5, .value = 55.0 },
    .{ .t = 3.0, .value = 220.0 },
};

const CurvePlayer = struct {
    pub const num_outputs = 2;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        rel_freq: f32,
    };

    carrier_curve: mod.Curve,
    carrier: mod.SineOsc,
    modulator_curve: mod.Curve,
    modulator: mod.SineOsc,

    fn init() CurvePlayer {
        return .{
            .carrier_curve = mod.Curve.init(),
            .carrier = mod.SineOsc.init(),
            .modulator_curve = mod.Curve.init(),
            .modulator = mod.SineOsc.init(),
        };
    }

    fn paint(
        self: *CurvePlayer,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        const freq_mul = params.rel_freq;

        zang.zero(span, temps[0]);
        self.modulator_curve.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .function = .smoothstep,
            .curve = &modulator_curve,
        });
        zang.multiplyWithScalar(span, temps[0], freq_mul);

        zang.zero(span, temps[1]);
        self.modulator.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[0]),
            .phase = zang.constant(0.0),
        });

        zang.zero(span, temps[0]);
        self.carrier_curve.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .function = .smoothstep,
            .curve = &carrier_curve,
        });
        zang.multiplyWithScalar(span, temps[0], freq_mul);

        self.carrier.paint(span, .{outputs[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[0]),
            .phase = zang.buffer(temps[1]),
        });

        zang.addInto(span, outputs[1], temps[0]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 2;
    pub const num_temps = 2;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;
    pub const output_sync_oscilloscope = 1;

    iq: zang.Notes(CurvePlayer.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    player: CurvePlayer,
    trigger: zang.Trigger(CurvePlayer.Params),

    pub fn init() MainModule {
        return .{
            .iq = zang.Notes(CurvePlayer.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .player = CurvePlayer.init(),
            .trigger = zang.Trigger(CurvePlayer.Params).init(),
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
            self.player.paint(result.span, outputs, temps, result.note_id_changed, result.params);
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (common.getKeyRelFreq(key)) |rel_freq| {
            if (down) {
                self.iq.push(impulse_frame, self.idgen.nextId(), .{
                    .sample_rate = AUDIO_SAMPLE_RATE,
                    .rel_freq = rel_freq,
                });
            }
            return true;
        }
        return false;
    }
};
