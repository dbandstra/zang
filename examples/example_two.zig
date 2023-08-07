const std = @import("std");
const zang = @import("zang");
const mod = @import("modules");
const common = @import("common");
const c = common.c;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_two
    \\
    \\A single instrument triggered by two input sources.
    \\Play the lower half of the keyboard to control the
    \\note frequency. Press the number keys to change the
    \\"colour" of the oscillator - from triangle to
    \\sawtooth. Both input sources trigger the envelope.
;

const a4 = 880.0;

pub const MainModule = struct {
    pub const num_outputs = 2;
    pub const num_temps = 2;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;
    pub const output_sync_oscilloscope = 1;

    pub const Params0 = struct { freq: f32, note_on: bool };
    pub const Params1 = struct { color: f32, note_on: bool };

    first: bool,

    osc: mod.TriSawOsc,
    env: mod.Envelope,

    key0: ?i32,
    iq0: zang.Notes(Params0).ImpulseQueue,
    idgen0: zang.IdGenerator,
    trig0: zang.Trigger(Params0),

    key1: ?i32,
    iq1: zang.Notes(Params1).ImpulseQueue,
    idgen1: zang.IdGenerator,
    trig1: zang.Trigger(Params1),

    pub fn init() MainModule {
        return .{
            .first = true,
            .osc = mod.TriSawOsc.init(),
            .env = mod.Envelope.init(),
            .key0 = null,
            .iq0 = zang.Notes(Params0).ImpulseQueue.init(),
            .idgen0 = zang.IdGenerator.init(),
            .trig0 = zang.Trigger(Params0).init(),
            .key1 = null,
            .iq1 = zang.Notes(Params1).ImpulseQueue.init(),
            .idgen1 = zang.IdGenerator.init(),
            .trig1 = zang.Trigger(Params1).init(),
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        if (self.first) {
            self.first = false;
            self.iq0.push(0, self.idgen0.nextId(), .{
                .freq = a4 * 0.5,
                .note_on = false,
            });
            self.iq1.push(0, self.idgen1.nextId(), .{
                .color = 0.5,
                .note_on = false,
            });
        }

        zang.zero(span, temps[0]);
        zang.zero(span, temps[1]);

        // note: this can be promoted to a library feature if i ever find a
        // non-dubious use for it.
        // as a library feature it would probably take the form of a new
        // iterator that consumes two source iterators (ctr0 and ctr1).
        // it could probably be made general to any number of source iterators.
        // what to do with note_on and note_id_changed is not obvious...

        var ctr0 = self.trig0.counter(span, self.iq0.consume());
        var ctr1 = self.trig1.counter(span, self.iq1.consume());

        var maybe_result0 = self.trig0.next(&ctr0);
        var maybe_result1 = self.trig1.next(&ctr1);

        var start = span.start;

        while (start < span.end) {
            // only paint if both impulse queues are active
            if (maybe_result0) |result0| {
                if (maybe_result1) |result1| {
                    const inner_span: zang.Span = .{
                        .start = start,
                        .end = @min(result0.span.end, result1.span.end),
                    };
                    zang.addScalarInto(inner_span, outputs[1], result0.params.freq);
                    self.osc.paint(
                        inner_span,
                        .{temps[0]},
                        .{},
                        false,
                        .{
                            .sample_rate = AUDIO_SAMPLE_RATE,
                            .freq = zang.constant(result0.params.freq),
                            .color = result1.params.color,
                        },
                    );
                    self.env.paint(
                        inner_span,
                        .{temps[1]},
                        .{},
                        // only reset the envelope when a button is depressed when
                        // no buttons were previous depressed
                        (result0.note_id_changed and result0.params.note_on and
                            !result1.note_id_changed) or (result1.note_id_changed and result1.params.note_on and
                            !result0.note_id_changed),
                        .{
                            .sample_rate = AUDIO_SAMPLE_RATE,
                            .attack = .{ .cubed = 0.025 },
                            .decay = .{ .cubed = 0.1 },
                            .release = .{ .cubed = 1.0 },
                            .sustain_volume = 0.5,
                            .note_on = result0.params.note_on or result1.params.note_on,
                        },
                    );
                    if (result0.span.end == inner_span.end) {
                        maybe_result0 = self.trig0.next(&ctr0);
                    }
                    if (result1.span.end == inner_span.end) {
                        maybe_result1 = self.trig1.next(&ctr1);
                    }
                    start = inner_span.end;
                    continue;
                }
            }

            break;
        }

        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (common.getKeyRelFreqFromRow(0, key)) |rel_freq| {
            if (down or (if (self.key0) |nh| nh == key else false)) {
                self.key0 = if (down) key else null;
                self.iq0.push(impulse_frame, self.idgen0.nextId(), .{
                    .freq = a4 * rel_freq,
                    .note_on = down,
                });
            }
        }
        if (key >= c.SDLK_1 and key <= c.SDLK_9) {
            const f = @as(f32, @floatFromInt(key - c.SDLK_1)) / @as(f32, @floatFromInt(c.SDLK_9 - c.SDLK_1));
            if (down or (if (self.key1) |nh| nh == key else false)) {
                self.key1 = if (down) key else null;
                self.iq1.push(impulse_frame, self.idgen1.nextId(), .{
                    .color = 0.5 + std.math.sqrt(f) * 0.5,
                    .note_on = down,
                });
            }
        }
        return true;
    }
};
