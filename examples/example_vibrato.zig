const zang = @import("zang");
const mod = @import("modules");
const note_frequencies = @import("zang-12tet");
const common = @import("common");
const c = common.c;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_vibrato
;

const a4 = 440.0;

pub const Instrument = struct {
    pub const num_outputs = 2;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    osc: mod.PulseOsc,
    gate: mod.Gate,
    vib: mod.SineOsc,

    pub fn init() Instrument {
        return .{
            .osc = mod.PulseOsc.init(),
            .gate = mod.Gate.init(),
            .vib = mod.SineOsc.init(),
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
        zang.zero(span, temps[2]);
        self.vib.paint(span, .{temps[2]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.constant(4.0),
            .phase = zang.constant(0.0),
        });
        var i = span.start;
        while (i < span.end) : (i += 1) {
            temps[2][i] = params.freq * (1.0 + 0.02 * temps[2][i]);
        }
        zang.addInto(span, outputs[1], temps[2]); // output the frequency for syncing the oscilloscope
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[2]),
            .color = 0.5,
        });
        zang.zero(span, temps[1]);
        self.gate.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 2;
    pub const num_temps = 3;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;
    pub const output_sync_oscilloscope = 1;

    key0: ?i32,
    iq0: zang.Notes(Instrument.Params).ImpulseQueue,
    idgen0: zang.IdGenerator,
    instr0: Instrument,
    trig0: zang.Trigger(Instrument.Params),

    pub fn init() MainModule {
        return .{
            .key0 = null,
            .iq0 = zang.Notes(Instrument.Params).ImpulseQueue.init(),
            .idgen0 = zang.IdGenerator.init(),
            .instr0 = Instrument.init(),
            .trig0 = zang.Trigger(Instrument.Params).init(),
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        var ctr0 = self.trig0.counter(span, self.iq0.consume());
        while (self.trig0.next(&ctr0)) |result| {
            self.instr0.paint(
                result.span,
                outputs,
                temps,
                result.note_id_changed,
                result.params,
            );
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (common.getKeyRelFreq(key)) |rel_freq| {
            if (down or (if (self.key0) |nh| nh == key else false)) {
                self.key0 = if (down) key else null;
                self.iq0.push(impulse_frame, self.idgen0.nextId(), .{
                    .sample_rate = AUDIO_SAMPLE_RATE,
                    .freq = a4 * rel_freq,
                    .note_on = down,
                });
            }
        }
        return true;
    }
};
