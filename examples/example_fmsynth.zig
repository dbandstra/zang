const std = @import("std");
const zang = @import("zang");
const mod = @import("modules");
const note_frequencies = @import("zang-12tet");
const common = @import("common.zig");
const c = @import("common/c.zig");

// TODO move vibrato and tremolo oscillators out of the Instrument. the same
// value should be shared by all voices

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_fmsynth
;

const a4 = 440.0;
const polyphony = 8;

fn decibels(db: f32) f32 {
    return std.math.pow(f32, 10, db / 20);
}

const Oscillator = struct {
    pub const num_outputs = 1;
    pub const num_temps = 0;
    pub const Params = struct {
        sample_rate: f32,
        waveform: u2,
        freq: []const f32,
        phase: ?[]const f32,
        feedback: f32,
    };

    t: f32,
    feedback1: f32,
    feedback2: f32,

    pub fn init() @This() {
        return .{
            .t = 0.0,
            .feedback1 = 0,
            .feedback2 = 0,
        };
    }

    pub fn paint(
        self: *@This(),
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        const output = outputs[0][span.start..span.end];

        var t = self.t;
        // it actually goes out of tune without this!...
        defer self.t = t - std.math.trunc(t);

        const inv_sample_rate = 1.0 / params.sample_rate;

        var i: usize = 0;
        while (i < output.len) : (i += 1) {
            const phase = if (params.phase) |p| p[span.start + i] else 0;
            const feedback = (self.feedback1 + self.feedback2) * params.feedback;

            const p = (t + phase) * std.math.pi * 2 + feedback;
            const s = std.math.sin(p);
            const sample = switch (params.waveform) {
                0 => s,
                1 => std.math.max(s, 0),
                2 => std.math.fabs(s),
                3 => if (std.math.sin(p * 2) >= 0) std.math.fabs(s) else 0,
            };

            output[i] += sample;

            t += params.freq[span.start + i] * inv_sample_rate;
            self.feedback2 = self.feedback1;
            self.feedback1 = sample;
        }
    }
};

// operator is one oscillator + envelope.
const Operator = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
        freq_mul: u32,
        waveform: u32,
        volume: u32,
        attack: u32,
        decay: u32,
        sustain: u32,
        release: u32,
        feedback: u32,
        tremolo: u32,
        vibrato: u32,
        phase: ?[]const f32,
        tremolo_input: []const f32,
        vibrato_input: []const f32,
    };

    osc: Oscillator,
    env: mod.Envelope,

    pub fn init() Operator {
        return .{
            .osc = Oscillator.init(),
            .env = mod.Envelope.init(),
        };
    }

    pub fn paint(
        self: *Operator,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        // translate discrete parameters to real values
        const freq_mul: f32 = switch (params.freq_mul) {
            0 => 0.5,
            1...10 => |x| @intToFloat(f32, x),
            11 => 10.0,
            12 => 12.0,
            13 => 12.0,
            14 => 15.0,
            15 => 15.0,
            else => unreachable,
        };

        // 0 is the loudest, 63 is the quietest.
        const volume = blk: {
            var db: f32 = 0;
            if (params.volume & 32 != 0) db -= 24.0;
            if (params.volume & 16 != 0) db -= 12.0;
            if (params.volume & 8 != 0) db -= 6.0;
            if (params.volume & 4 != 0) db -= 3.0;
            if (params.volume & 2 != 0) db -= 1.5;
            if (params.volume & 1 != 0) db -= 0.75;
            break :blk decibels(db);
        };

        // no idea how these correspond to actual OPL, i just made them up.
        // i didn't mimic OPL's behavior of 0 meaning "never attack/decay/release"
        const attack = 0.002 + 4.0 * std.math.pow(f32, 1 - @intToFloat(f32, params.attack) / 15.0, 3.0);

        const decay = 0.002 + 4.0 * std.math.pow(f32, 1 - @intToFloat(f32, params.decay) / 15.0, 3.0);
        const sustain = blk: {
            var db: f32 = 0;
            if (params.sustain & 8 != 0) db -= 24.0;
            if (params.sustain & 4 != 0) db -= 12.0;
            if (params.sustain & 2 != 0) db -= 6.0;
            if (params.sustain & 1 != 0) db -= 3.0;
            break :blk decibels(db);
        };
        const release = 0.002 + 4.0 * std.math.pow(f32, 1 - @intToFloat(f32, params.release) / 15.0, 3.0);

        // note: OPL chip lets you set globally one of two tremolo depths. -4.8dB or -1.0dB.
        const tremolo: f32 = switch (params.tremolo) {
            0 => 0,
            1 => 1 - decibels(-4.8),
            else => unreachable,
        };

        // same with vibrato, there are two depths. 7 cent and 14 cent. a cent is 1/100 of a
        // semitone. so there are 1200 cents in an octave.
        // i'm not sure if i got this math right. this is barely perceptible and this is the
        // bigger of the two depths. maybe this is how the chips were?
        const vibrato: f32 = switch (params.vibrato) {
            0 => 0.0,
            1 => std.math.pow(f32, 2, 14.0 / 1200.0) - 1,
            else => unreachable,
        };

        const feedback: f32 = switch (params.feedback) {
            0 => 0.0,
            1 => std.math.pi / 16.0,
            2 => std.math.pi / 8.0,
            3 => std.math.pi / 4.0,
            4 => std.math.pi / 2.0,
            5 => std.math.pi,
            6 => std.math.pi * 2.0,
            7 => std.math.pi * 4.0,
            else => unreachable,
        };

        // temp1 = input frequency for oscillator
        zang.zero(span, temps[1]);
        zang.multiplyScalar(span, temps[1], params.vibrato_input, vibrato);
        zang.addScalarInto(span, temps[1], 1.0);
        zang.multiplyWithScalar(span, temps[1], params.freq * freq_mul);

        // temp0 = oscillator output with volume level applied
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = temps[1],
            .waveform = @truncate(u2, params.waveform),
            .phase = params.phase,
            .feedback = feedback,
        });
        zang.multiplyWithScalar(span, temps[0], volume);

        // apply tremolo to temp0
        zang.zero(span, temps[1]);
        zang.multiplyScalar(span, temps[1], params.tremolo_input, tremolo);
        zang.addScalarInto(span, temps[1], 1.0);
        zang.multiplyWith(span, temps[0], temps[1]);

        // temp1 = envelope
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = attack },
            .decay = .{ .cubed = decay },
            .sustain_volume = sustain,
            .release = .{ .cubed = release },
            .note_on = params.note_on,
        });

        // output
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

const Instrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        tremolo_input: []const f32,
        vibrato_input: []const f32,
        modulator_freq_mul: u32,
        modulator_waveform: u32,
        modulator_volume: u32,
        modulator_attack: u32,
        modulator_decay: u32,
        modulator_sustain: u32,
        modulator_release: u32,
        modulator_feedback: u32,
        modulator_tremolo: u32,
        modulator_vibrato: u32,
        carrier_freq_mul: u32,
        carrier_waveform: u32,
        carrier_volume: u32,
        carrier_attack: u32,
        carrier_decay: u32,
        carrier_sustain: u32,
        carrier_release: u32,
        carrier_tremolo: u32,
        carrier_vibrato: u32,
        freq: f32,
        note_on: bool,
    };

    modulator: Operator,
    carrier: Operator,

    pub fn init() Instrument {
        return .{
            .modulator = Operator.init(),
            .carrier = Operator.init(),
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
        // temp0 = modulator output
        zang.zero(span, temps[0]);
        self.modulator.paint(span, .{temps[0]}, .{ temps[1], temps[2] }, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = params.freq,
            .note_on = params.note_on,
            .freq_mul = params.modulator_freq_mul,
            .waveform = params.modulator_waveform,
            .volume = params.modulator_volume,
            .attack = params.modulator_attack,
            .decay = params.modulator_decay,
            .sustain = params.modulator_sustain,
            .release = params.modulator_release,
            .feedback = params.modulator_feedback,
            .tremolo = params.modulator_tremolo,
            .vibrato = params.modulator_vibrato,
            .phase = null,
            .tremolo_input = params.tremolo_input,
            .vibrato_input = params.vibrato_input,
        });

        // output from carrier
        self.carrier.paint(span, .{outputs[0]}, .{ temps[1], temps[2] }, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = params.freq,
            .note_on = params.note_on,
            .freq_mul = params.carrier_freq_mul,
            .waveform = params.carrier_waveform,
            .volume = params.carrier_volume,
            .attack = params.carrier_attack,
            .decay = params.carrier_decay,
            .sustain = params.carrier_sustain,
            .release = params.carrier_release,
            .feedback = 0,
            .tremolo = params.carrier_tremolo,
            .vibrato = params.carrier_vibrato,
            .phase = temps[0],
            .tremolo_input = params.tremolo_input,
            .vibrato_input = params.vibrato_input,
        });
    }
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = Instrument.num_temps + 2;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    const NoteParams = struct {
        freq: f32,
        note_on: bool,
    };

    const Voice = struct {
        module: Instrument,
        trigger: zang.Trigger(NoteParams),
    };

    parameters: [19]common.Parameter = [_]common.Parameter{
        // note: OPL chips have 64 values for volume (output level), i chose just 16 for now
        .{ .desc = "Modulator frequency multiplier:", .num_values = 16, .current_value = 2 },
        .{ .desc = "Modulator waveform:", .num_values = 4, .current_value = 0 },
        .{ .desc = "Modulator volume:  ", .num_values = 64, .current_value = 0 },
        .{ .desc = "Modulator attack:  ", .num_values = 16, .current_value = 8 },
        .{ .desc = "Modulator decay:   ", .num_values = 16, .current_value = 8 },
        .{ .desc = "Modulator sustain: ", .num_values = 16, .current_value = 1 },
        .{ .desc = "Modulator release: ", .num_values = 16, .current_value = 8 },
        .{ .desc = "Modulator tremolo: ", .num_values = 2, .current_value = 0 },
        .{ .desc = "Modulator vibrato: ", .num_values = 2, .current_value = 0 },
        .{ .desc = "Modulator feedback:", .num_values = 8, .current_value = 0 },
        .{ .desc = "Carrier frequency multiplier:", .num_values = 16, .current_value = 1 },
        .{ .desc = "Carrier waveform:", .num_values = 4, .current_value = 0 },
        .{ .desc = "Carrier volume:  ", .num_values = 64, .current_value = 0 },
        .{ .desc = "Carrier attack:  ", .num_values = 16, .current_value = 8 },
        .{ .desc = "Carrier decay:   ", .num_values = 16, .current_value = 8 },
        .{ .desc = "Carrier sustain: ", .num_values = 16, .current_value = 1 },
        .{ .desc = "Carrier release: ", .num_values = 16, .current_value = 8 },
        .{ .desc = "Carrier tremolo: ", .num_values = 2, .current_value = 0 },
        .{ .desc = "Carrier vibrato: ", .num_values = 2, .current_value = 0 },
    },

    dispatcher: zang.Notes(NoteParams).PolyphonyDispatcher(polyphony),
    voices: [polyphony]Voice,

    note_ids: [common.key_bindings.len]?usize,
    next_note_id: usize,

    iq: zang.Notes(NoteParams).ImpulseQueue,

    vibrato_lfo: mod.SineOsc,
    tremolo_lfo: mod.SineOsc,

    pub fn init() MainModule {
        var self: MainModule = .{
            .note_ids = [1]?usize{null} ** common.key_bindings.len,
            .next_note_id = 1,
            .iq = zang.Notes(NoteParams).ImpulseQueue.init(),
            .dispatcher = zang.Notes(NoteParams).PolyphonyDispatcher(polyphony).init(),
            .voices = undefined,
            .vibrato_lfo = mod.SineOsc.init(),
            .tremolo_lfo = mod.SineOsc.init(),
        };
        for (self.voices) |*voice| {
            voice.* = .{
                .module = Instrument.init(),
                .trigger = zang.Trigger(NoteParams).init(),
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
        // temp0 = tremolo lfo
        zang.zero(span, temps[0]);
        self.tremolo_lfo.paint(span, .{temps[0]}, .{}, false, .{
            .sample_rate = AUDIO_SAMPLE_RATE,
            .freq = zang.constant(3.7),
            .phase = zang.constant(0),
        });

        // temp1 = vibrato lfo
        zang.zero(span, temps[1]);
        self.vibrato_lfo.paint(span, .{temps[1]}, .{}, false, .{
            .sample_rate = AUDIO_SAMPLE_RATE,
            .freq = zang.constant(6.4),
            .phase = zang.constant(0),
        });

        // FM voices with polyphony
        const iap = self.iq.consume();

        const poly_iap = self.dispatcher.dispatch(iap);

        for (self.voices) |*voice, i| {
            var ctr = voice.trigger.counter(span, poly_iap[i]);
            while (voice.trigger.next(&ctr)) |result| {
                voice.module.paint(
                    result.span,
                    .{outputs[0]},
                    .{ temps[2], temps[3], temps[4] },
                    result.note_id_changed,
                    .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .freq = result.params.freq,
                        .note_on = result.params.note_on,
                        .tremolo_input = temps[0],
                        .vibrato_input = temps[1],
                        .modulator_freq_mul = self.parameters[0].current_value,
                        .modulator_waveform = self.parameters[1].current_value,
                        .modulator_volume = self.parameters[2].current_value,
                        .modulator_attack = self.parameters[3].current_value,
                        .modulator_decay = self.parameters[4].current_value,
                        .modulator_sustain = self.parameters[5].current_value,
                        .modulator_release = self.parameters[6].current_value,
                        .modulator_tremolo = self.parameters[7].current_value,
                        .modulator_vibrato = self.parameters[8].current_value,
                        .modulator_feedback = self.parameters[9].current_value,
                        .carrier_freq_mul = self.parameters[10].current_value,
                        .carrier_waveform = self.parameters[11].current_value,
                        .carrier_volume = self.parameters[12].current_value,
                        .carrier_attack = self.parameters[13].current_value,
                        .carrier_decay = self.parameters[14].current_value,
                        .carrier_sustain = self.parameters[15].current_value,
                        .carrier_release = self.parameters[16].current_value,
                        .carrier_tremolo = self.parameters[17].current_value,
                        .carrier_vibrato = self.parameters[18].current_value,
                    },
                );
            }
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        for (common.key_bindings) |kb, i| {
            if (kb.key != key)
                continue;

            const params: NoteParams = .{
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
