// TODO - maybe add an envelope effect at the outer level, to demonstrate that
// the note events are nesting correctly

const zang = @import("zang");
const note_frequencies = @import("zang-12tet");
const mod = @import("modules");
const common = @import("common");
const c = common.c;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_subsong
    \\
    \\Play with the keyboard - a little melody is played
    \\with each keypress. This demonstrates "notes within
    \\notes".
;

const a4 = 440.0;

const InnerInstrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    osc: mod.TriSawOsc,
    env: mod.Envelope,

    fn init() InnerInstrument {
        return .{
            .osc = mod.TriSawOsc.init(),
            .env = mod.Envelope.init(),
        };
    }

    fn paint(
        self: *InnerInstrument,
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
            .color = 0.0,
        });
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 0.025 },
            .decay = .{ .cubed = 0.1 },
            .release = .{ .cubed = 0.15 },
            .sustain_volume = 0.5,
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

const MyNoteParams = struct {
    freq: f32,
    note_on: bool,
};

fn makeNote(
    t: f32,
    id: usize,
    freq: f32,
    note_on: bool,
) zang.Notes(MyNoteParams).SongEvent {
    return .{
        .t = 0.1 * t,
        .note_id = id,
        .params = .{ .freq = freq, .note_on = note_on },
    };
}

// an example of a custom "module"
const SubtrackPlayer = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    pub const BaseFrequency = a4 * note_frequencies.c4;

    tracker: zang.Notes(MyNoteParams).NoteTracker,
    instr: InnerInstrument,
    trigger: zang.Trigger(MyNoteParams),

    fn init() SubtrackPlayer {
        const Notes = zang.Notes(MyNoteParams);
        const f = note_frequencies;

        return .{
            .tracker = Notes.NoteTracker.init(&[_]Notes.SongEvent{
                comptime makeNote(0.0, 1, a4 * f.c4, true),
                comptime makeNote(1.0, 2, a4 * f.ab3, true),
                comptime makeNote(2.0, 3, a4 * f.g3, true),
                comptime makeNote(3.0, 4, a4 * f.eb3, true),
                comptime makeNote(4.0, 5, a4 * f.c3, true),
                comptime makeNote(5.0, 5, a4 * f.c3, false),
            }),
            .instr = InnerInstrument.init(),
            .trigger = zang.Trigger(MyNoteParams).init(),
        };
    }

    fn paint(
        self: *SubtrackPlayer,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        if (params.note_on and note_id_changed) {
            self.tracker.reset();
            self.trigger.reset();
        }
        const iap = self.tracker.consume(params.sample_rate, span);
        var ctr = self.trigger.counter(span, iap);
        while (self.trigger.next(&ctr)) |result| {
            const new_note = (params.note_on and note_id_changed) or result.note_id_changed;
            self.instr.paint(result.span, outputs, temps, new_note, .{
                .sample_rate = params.sample_rate,
                .freq = result.params.freq * params.freq / BaseFrequency,
                .note_on = result.params.note_on,
            });
        }
    }
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    key: ?i32,
    iq: zang.Notes(SubtrackPlayer.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    player: SubtrackPlayer,
    trigger: zang.Trigger(SubtrackPlayer.Params),

    pub fn init() MainModule {
        return .{
            .key = null,
            .iq = zang.Notes(SubtrackPlayer.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .player = SubtrackPlayer.init(),
            .trigger = zang.Trigger(SubtrackPlayer.Params).init(),
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
        if (common.getKeyRelFreq(key)) |rel_freq| {
            if (down or (if (self.key) |nh| nh == key else false)) {
                self.key = if (down) key else null;
                self.iq.push(impulse_frame, self.idgen.nextId(), .{
                    .sample_rate = AUDIO_SAMPLE_RATE,
                    .freq = a4 * rel_freq,
                    .note_on = down,
                });
            }
            return true;
        }
        return false;
    }
};
