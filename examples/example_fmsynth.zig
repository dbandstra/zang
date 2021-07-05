const zang = @import("zang");
const mod = @import("modules");
const note_frequencies = @import("zang-12tet");
const common = @import("common.zig");
const c = @import("common/c.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_fmsynth
;

const a4 = 440.0;
const polyphony = 8;

// TODO modulator feedback
// TODO vibrato
// TODO tremolo
// TODO alternate waveforms
// TODO parameters have preset values you can pick from? they should be shown on the screen
// and you can click them?

const Instrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        modulator_freq_mul: f32,
        modulator_volume: f32,
        modulator_attack: f32,
        modulator_decay: f32,
        modulator_sustain: f32,
        modulator_release: f32,
        carrier_freq_mul: f32,
        carrier_volume: f32,
        carrier_attack: f32,
        carrier_decay: f32,
        carrier_sustain: f32,
        carrier_release: f32,
        freq: f32,
        note_on: bool,
    };

    modulator: mod.SineOsc,
    modulator_env: mod.Envelope,
    carrier: mod.SineOsc,
    carrier_env: mod.Envelope,

    pub fn init() Instrument {
        return .{
            .modulator = mod.SineOsc.init(),
            .modulator_env = mod.Envelope.init(),
            .carrier = mod.SineOsc.init(),
            .carrier_env = mod.Envelope.init(),
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
        // temp0 = modulator oscillator
        zang.zero(span, temps[0]);
        self.modulator.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.constant(params.freq * params.modulator_freq_mul),
            .phase = zang.constant(0.0),
        });
        zang.multiplyWithScalar(span, temps[0], params.modulator_volume);

        // temp1 = modulator envelope
        zang.zero(span, temps[1]);
        self.modulator_env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = params.modulator_attack },
            .decay = .{ .cubed = params.modulator_decay },
            .sustain_volume = params.modulator_sustain,
            .release = .{ .cubed = params.modulator_release },
            .note_on = params.note_on,
        });

        // temp0 = modulator with envelope applied
        zang.multiplyWith(span, temps[0], temps[1]);

        // temp1 = carrier oscillator
        zang.zero(span, temps[1]);
        self.carrier.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.constant(params.freq * params.carrier_freq_mul),
            .phase = zang.buffer(temps[0]),
        });
        zang.multiplyWithScalar(span, temps[1], params.carrier_volume);

        // temp2 = carrier envelope
        zang.zero(span, temps[2]);
        self.carrier_env.paint(span, .{temps[2]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = params.carrier_attack },
            .decay = .{ .cubed = params.carrier_decay },
            .sustain_volume = params.carrier_sustain,
            .release = .{ .cubed = params.carrier_release },
            .note_on = params.note_on,
        });

        // temp1 = carrier with envelope applied
        zang.multiplyWith(span, temps[1], temps[2]);

        // output
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    const Voice = struct {
        module: Instrument,
        trigger: zang.Trigger(Instrument.Params),
    };

    parameters: [12]common.Parameter = [_]common.Parameter{
        .{ .desc = "Modulator frequency multiplier", .value = 2.0 },
        .{ .desc = "Modulator volume", .value = 1.0 },
        .{ .desc = "Modulator attack", .value = 0.025 },
        .{ .desc = "Modulator decay", .value = 0.1 },
        .{ .desc = "Modulator sustain", .value = 0.5 },
        .{ .desc = "Modulator release", .value = 1.0 },
        .{ .desc = "Carrier frequency multiplier", .value = 1.0 },
        .{ .desc = "Carrier volume", .value = 1.0 },
        .{ .desc = "Carrier attack", .value = 0.025 },
        .{ .desc = "Carrier decay", .value = 0.1 },
        .{ .desc = "Carrier sustain", .value = 0.5 },
        .{ .desc = "Carrier release", .value = 1.0 },
    },

    dispatcher: zang.Notes(Instrument.Params).PolyphonyDispatcher(polyphony),
    voices: [polyphony]Voice,

    note_ids: [common.key_bindings.len]?usize,
    next_note_id: usize,

    iq: zang.Notes(Instrument.Params).ImpulseQueue,

    pub fn init() MainModule {
        var self: MainModule = .{
            .note_ids = [1]?usize{null} ** common.key_bindings.len,
            .next_note_id = 1,
            .iq = zang.Notes(Instrument.Params).ImpulseQueue.init(),
            .dispatcher = zang.Notes(Instrument.Params).PolyphonyDispatcher(polyphony).init(),
            .voices = undefined,
        };
        var i: usize = 0;
        while (i < polyphony) : (i += 1) {
            self.voices[i] = .{
                .module = Instrument.init(),
                .trigger = zang.Trigger(Instrument.Params).init(),
            };
        }
        return self;
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        const iap = self.iq.consume();

        const poly_iap = self.dispatcher.dispatch(iap);

        for (self.voices) |*voice, i| {
            var ctr = voice.trigger.counter(span, poly_iap[i]);
            while (voice.trigger.next(&ctr)) |result| {
                voice.module.paint(
                    result.span,
                    outputs,
                    temps,
                    result.note_id_changed,
                    result.params,
                );
            }
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        for (common.key_bindings) |kb, i| {
            if (kb.key != key)
                continue;

            const params: Instrument.Params = .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .modulator_freq_mul = self.parameters[0].value,
                .modulator_volume = self.parameters[1].value,
                .modulator_attack = self.parameters[2].value,
                .modulator_decay = self.parameters[3].value,
                .modulator_sustain = self.parameters[4].value,
                .modulator_release = self.parameters[5].value,
                .carrier_freq_mul = self.parameters[6].value,
                .carrier_volume = self.parameters[7].value,
                .carrier_attack = self.parameters[8].value,
                .carrier_decay = self.parameters[9].value,
                .carrier_sustain = self.parameters[10].value,
                .carrier_release = self.parameters[11].value,
                .freq = a4 * kb.rel_freq,
                .note_on = down,
            };

            if (down) {
                self.iq.push(impulse_frame, self.next_note_id, params);
                self.note_ids[i] = self.next_note_id;
                self.next_note_id += 1;
            } else if (self.note_ids[i]) |note_id| {
                self.iq.push(impulse_frame, note_id, params);
                self.note_ids[i] = null;
            }
        }
        return true;
    }
};
