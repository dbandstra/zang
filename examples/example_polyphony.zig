// this a "brute force" approach to polyphony... every possible note gets its
// own voice that is always running. well, it works

const zang = @import("zang");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");
const Instrument = @import("modules.zig").NiceInstrument;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_polyphony
    \\
    \\Play an instrument with the keyboard. You can hold
    \\down multiple notes.
    \\
    \\Press spacebar to cycle through various amounts of
    \\decimation (artificial sample rate reduction).
;

const a4 = 220.0;

const Polyphony = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        note_held: [common.key_bindings.len]bool,
    };

    const Voice = struct {
        down: bool,
        iq: zang.Notes(Instrument.Params).ImpulseQueue,
        idgen: zang.IdGenerator,
        instrument: Instrument,
        trigger: zang.Trigger(Instrument.Params),
    };

    voices: [common.key_bindings.len]Voice,

    fn init() Polyphony {
        var self: Polyphony = .{
            .voices = undefined,
        };
        var i: usize = 0;
        while (i < common.key_bindings.len) : (i += 1) {
            self.voices[i] = Voice{
                .down = false,
                .iq = zang.Notes(Instrument.Params).ImpulseQueue.init(),
                .idgen = zang.IdGenerator.init(),
                .instrument = Instrument.init(0.3),
                .trigger = zang.Trigger(Instrument.Params).init(),
            };
        }
        return self;
    }

    fn paint(
        self: *Polyphony,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        params: Params,
    ) void {
        var i: usize = 0;
        while (i < common.key_bindings.len) : (i += 1) {
            if (params.note_held[i] != self.voices[i].down) {
                self.voices[i].iq.push(0, self.voices[i].idgen.nextId(), .{
                    .sample_rate = params.sample_rate,
                    .freq = a4 * common.key_bindings[i].rel_freq,
                    .note_on = params.note_held[i],
                });
                self.voices[i].down = params.note_held[i];
            }
        }

        for (self.voices) |*voice| {
            var ctr = voice.trigger.counter(span, voice.iq.consume());
            while (voice.trigger.next(&ctr)) |result| {
                voice.instrument.paint(
                    result.span,
                    outputs,
                    temps,
                    result.note_id_changed,
                    result.params,
                );
            }
        }
    }
};

const MyDecimatorParams = struct {
    bypass: bool,
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    current_params: Polyphony.Params,
    iq: zang.Notes(Polyphony.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    polyphony: Polyphony,
    trigger: zang.Trigger(Polyphony.Params),
    dec: mod.Decimator,
    dec_mode: u32,

    pub fn init() MainModule {
        return .{
            .current_params = .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .note_held = [1]bool{false} ** common.key_bindings.len,
            },
            .iq = zang.Notes(Polyphony.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .polyphony = Polyphony.init(),
            .trigger = zang.Trigger(Polyphony.Params).init(),
            .dec = mod.Decimator.init(),
            .dec_mode = 0,
        };
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        zang.zero(span, temps[2]);

        var ctr = self.trigger.counter(span, self.iq.consume());
        while (self.trigger.next(&ctr)) |result| {
            self.polyphony.paint(
                result.span,
                .{temps[2]},
                .{ temps[0], temps[1] },
                result.params,
            );
        }

        if (self.dec_mode > 0) {
            self.dec.paint(span, outputs, .{}, false, .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .input = temps[2],
                .fake_sample_rate = switch (self.dec_mode) {
                    1 => 6000.0,
                    2 => 5000.0,
                    3 => 4000.0,
                    4 => 3000.0,
                    5 => 2000.0,
                    6 => 1000.0,
                    else => unreachable,
                },
            });
        } else {
            zang.addInto(span, outputs[0], temps[2]);
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (key == c.SDLK_SPACE and down) {
            self.dec_mode = (self.dec_mode + 1) % 7;
            return false;
        }
        for (common.key_bindings) |kb, i| {
            if (kb.key == key) {
                self.current_params.note_held[i] = down;
                self.iq.push(impulse_frame, self.idgen.nextId(), self.current_params);
            }
        }
        return true;
    }
};
