const zang = @import("zang");
const note_frequencies = @import("zang-12tet");
const common = @import("common");
const c = common.c;
const PMOscInstrument = @import("modules.zig").PMOscInstrument;
const FilteredSawtoothInstrument = @import("modules.zig").FilteredSawtoothInstrument;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_play
    \\
    \\Play a simple monophonic synthesizer with the
    \\keyboard.
    \\
    \\Press spacebar to create a low drone in another voice.
;

const a4 = 440.0;

pub const MainModule = struct {
    pub const num_outputs = 2;
    pub const num_temps = 3;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;
    pub const output_sync_oscilloscope = 1;

    key0: ?i32,
    iq0: zang.Notes(PMOscInstrument.Params).ImpulseQueue,
    idgen0: zang.IdGenerator,
    instr0: PMOscInstrument,
    trig0: zang.Trigger(PMOscInstrument.Params),
    iq1: zang.Notes(FilteredSawtoothInstrument.Params).ImpulseQueue,
    idgen1: zang.IdGenerator,
    instr1: FilteredSawtoothInstrument,
    trig1: zang.Trigger(FilteredSawtoothInstrument.Params),

    pub fn init() MainModule {
        return .{
            .key0 = null,
            .iq0 = zang.Notes(PMOscInstrument.Params).ImpulseQueue.init(),
            .idgen0 = zang.IdGenerator.init(),
            .instr0 = PMOscInstrument.init(1.0),
            .trig0 = zang.Trigger(PMOscInstrument.Params).init(),
            .iq1 = zang.Notes(FilteredSawtoothInstrument.Params).ImpulseQueue.init(),
            .idgen1 = zang.IdGenerator.init(),
            .instr1 = FilteredSawtoothInstrument.init(),
            .trig1 = zang.Trigger(FilteredSawtoothInstrument.Params).init(),
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
                .{outputs[0]},
                .{ temps[0], temps[1], temps[2] },
                result.note_id_changed,
                result.params,
            );
            zang.addScalarInto(result.span, outputs[1], result.params.freq);
        }
        var ctr1 = self.trig1.counter(span, self.iq1.consume());
        while (self.trig1.next(&ctr1)) |result| {
            self.instr1.paint(
                result.span,
                .{outputs[0]},
                .{ temps[0], temps[1], temps[2] },
                result.note_id_changed,
                result.params,
            );
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (key == c.SDLK_SPACE) {
            const freq = a4 * note_frequencies.c4 / 4.0;
            self.iq1.push(impulse_frame, self.idgen1.nextId(), .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .freq = zang.constant(freq),
                .note_on = down,
            });
        } else if (common.getKeyRelFreq(key)) |rel_freq| {
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
