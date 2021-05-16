const zang = @import("zang");
const note_frequencies = @import("zang-12tet");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_envelope
    \\
    \\Basic example demonstrating the ADSR envelope. Press
    \\spacebar to trigger the envelope.
;

const a4 = 440.0;

pub const Instrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    osc: mod.PulseOsc,
    env: mod.Envelope,

    pub fn init() Instrument {
        return .{
            .osc = mod.PulseOsc.init(),
            .env = mod.Envelope.init(),
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
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.constant(params.freq),
            .color = 0.5,
        });
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 1.0 },
            .decay = .{ .cubed = 1.0 },
            .release = .{ .cubed = 1.0 },
            .sustain_volume = 0.5,
            .note_on = params.note_on,
        });
        zang.multiplyWithScalar(span, temps[1], 5.0);
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    iq: zang.Notes(Instrument.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    instr: Instrument,
    trig: zang.Trigger(Instrument.Params),

    pub fn init() MainModule {
        return .{
            .iq = zang.Notes(Instrument.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .instr = Instrument.init(),
            .trig = zang.Trigger(Instrument.Params).init(),
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        var ctr = self.trig.counter(span, self.iq.consume());
        while (self.trig.next(&ctr)) |result| {
            self.instr.paint(
                result.span,
                outputs,
                temps,
                result.note_id_changed,
                result.params,
            );
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (key == c.SDLK_SPACE) {
            const freq = a4 * note_frequencies.c2;
            self.iq.push(impulse_frame, self.idgen.nextId(), .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .freq = freq,
                .note_on = down,
            });
            return true;
        }
        return false;
    }
};
