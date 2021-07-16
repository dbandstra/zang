const std = @import("std");
const zang = @import("zang");
const mod = @import("modules");
const note_frequencies = @import("zang-12tet");

pub const PhaseModOscillator = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        relative: bool,
        // ratio: the carrier oscillator will use whatever frequency you give
        // the PhaseModOscillator. the modulator oscillator will multiply the
        // frequency by this ratio. for example, a ratio of 0.5 means that the
        // modulator oscillator will always play at half the frequency of the
        // carrier oscillator
        ratio: zang.ConstantOrBuffer,
        // multiplier: the modulator oscillator's output is multiplied by this
        // before it is fed in to the phase input of the carrier oscillator.
        multiplier: zang.ConstantOrBuffer,
    };

    carrier: mod.SineOsc,
    modulator: mod.SineOsc,

    pub fn init() PhaseModOscillator {
        return .{
            .carrier = mod.SineOsc.init(),
            .modulator = mod.SineOsc.init(),
        };
    }

    pub fn paint(
        self: *PhaseModOscillator,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        switch (params.ratio) {
            .constant => |ratio| {
                if (params.relative) {
                    zang.set(span, temps[0], params.freq * ratio);
                } else {
                    zang.set(span, temps[0], ratio);
                }
            },
            .buffer => |ratio| {
                if (params.relative) {
                    zang.multiplyScalar(span, temps[0], ratio, params.freq);
                } else {
                    zang.copy(span, temps[0], ratio);
                }
            },
        }
        zang.zero(span, temps[1]);
        self.modulator.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.buffer(temps[0]),
            .phase = zang.constant(0.0),
        });
        zang.zero(span, temps[0]);
        switch (params.multiplier) {
            .constant => |multiplier| zang.multiplyScalar(span, temps[0], temps[1], multiplier),
            .buffer => |multiplier| zang.multiply(span, temps[0], temps[1], multiplier),
        }
        zang.zero(span, temps[1]);
        self.carrier.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = zang.constant(params.freq),
            .phase = zang.buffer(temps[0]),
        });
        zang.addInto(span, outputs[0], temps[1]);
    }
};

// PhaseModOscillator packaged with an envelope
pub const PMOscInstrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    release_duration: f32,
    osc: PhaseModOscillator,
    env: mod.Envelope,

    pub fn init(release_duration: f32) PMOscInstrument {
        return .{
            .release_duration = release_duration,
            .osc = PhaseModOscillator.init(),
            .env = mod.Envelope.init(),
        };
    }

    pub fn paint(
        self: *PMOscInstrument,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{ temps[1], temps[2] }, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = params.freq,
            .relative = true,
            .ratio = zang.constant(1.0),
            .multiplier = zang.constant(1.0),
        });
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 0.025 },
            .decay = .{ .cubed = 0.1 },
            .release = .{ .cubed = self.release_duration },
            .sustain_volume = 0.5,
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const FilteredSawtoothInstrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        freq: zang.ConstantOrBuffer,
        note_on: bool,
    };

    osc: mod.TriSawOsc,
    env: mod.Envelope,
    flt: mod.Filter,

    pub fn init() FilteredSawtoothInstrument {
        return .{
            .osc = mod.TriSawOsc.init(),
            .env = mod.Envelope.init(),
            .flt = mod.Filter.init(),
        };
    }

    pub fn paint(
        self: *FilteredSawtoothInstrument,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .freq = params.freq,
            .color = 0.0,
        });
        zang.multiplyWithScalar(span, temps[0], 1.5); // boost sawtooth volume
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 0.025 },
            .decay = .{ .cubed = 0.1 },
            .release = .{ .cubed = 1.0 },
            .sustain_volume = 0.5,
            .note_on = params.note_on,
        });
        zang.zero(span, temps[2]);
        zang.multiply(span, temps[2], temps[0], temps[1]);
        self.flt.paint(span, .{outputs[0]}, .{}, note_id_changed, .{
            .input = temps[2],
            .type = .low_pass,
            .cutoff = zang.constant(mod.Filter.cutoffFromFrequency(
                440.0 * note_frequencies.c5,
                params.sample_rate,
            )),
            .res = zang.constant(0.7),
        });
    }
};

pub const NiceInstrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    color: f32,
    osc: mod.PulseOsc,
    flt: mod.Filter,
    env: mod.Envelope,

    pub fn init(color: f32) NiceInstrument {
        return .{
            .color = color,
            .osc = mod.PulseOsc.init(),
            .flt = mod.Filter.init(),
            .env = mod.Envelope.init(),
        };
    }

    pub fn paint(
        self: *NiceInstrument,
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
            .color = self.color,
        });
        zang.multiplyWithScalar(span, temps[0], 0.5);
        zang.zero(span, temps[1]);
        self.flt.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .input = temps[0],
            .type = .low_pass,
            .cutoff = zang.constant(mod.Filter.cutoffFromFrequency(
                params.freq * 8.0,
                params.sample_rate,
            )),
            .res = zang.constant(0.7),
        });
        zang.zero(span, temps[0]);
        self.env.paint(span, .{temps[0]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 0.01 },
            .decay = .{ .cubed = 0.1 },
            .release = .{ .cubed = 0.5 },
            .sustain_volume = 0.8,
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const HardSquareInstrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    osc: mod.PulseOsc,
    gate: mod.Gate,

    pub fn init() HardSquareInstrument {
        return .{
            .osc = mod.PulseOsc.init(),
            .gate = mod.Gate.init(),
        };
    }

    pub fn paint(
        self: *HardSquareInstrument,
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
        self.gate.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const SquareWithEnvelope = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
    };

    weird: bool,
    osc: mod.PulseOsc,
    env: mod.Envelope,

    pub fn init(weird: bool) SquareWithEnvelope {
        return .{
            .weird = weird,
            .osc = mod.PulseOsc.init(),
            .env = mod.Envelope.init(),
        };
    }

    pub fn paint(
        self: *SquareWithEnvelope,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        zang.zero(span, temps[0]);
        self.osc.paint(span, .{temps[0]}, .{}, .{
            .sample_rate = params.sample_rate,
            .freq = zang.constant(params.freq),
            .color = if (self.weird) 0.3 else 0.5,
        });
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack_duration = 0.01,
            .decay_duration = 0.1,
            .sustain_volume = 0.5,
            .release_duration = 0.5,
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

// this is a module that simply delays the input signal. there's no dry output
// and no feedback (echoes)
pub fn SimpleDelay(comptime DELAY_SAMPLES: usize) type {
    return struct {
        pub const num_outputs = 1;
        pub const num_temps = 0;
        pub const Params = struct {
            input: []const f32,
        };

        delay: zang.Delay(DELAY_SAMPLES),

        pub fn init() @This() {
            return .{
                .delay = zang.Delay(DELAY_SAMPLES).init(),
            };
        }

        pub fn reset(self: *@This()) void {
            self.delay.reset();
        }

        pub fn paint(
            self: *@This(),
            span: zang.Span,
            outputs: [num_outputs][]f32,
            temps: [num_temps][]f32,
            note_id_changed: bool,
            params: Params,
        ) void {
            var start = span.start;
            const end = span.end;

            while (start < end) {
                const samples_read = self.delay.readDelayBuffer(outputs[0][start..end]);
                self.delay.writeDelayBuffer(
                    params.input[start .. start + samples_read],
                );
                start += samples_read;
            }
        }
    };
}

// this is a bit unusual, it filters the input and outputs it immediately. it's
// meant to be used after SimpleDelay (which provides the initial delay)
pub fn FilteredEchoes(comptime DELAY_SAMPLES: usize) type {
    return struct {
        pub const num_outputs = 1;
        pub const num_temps = 2;
        pub const Params = struct {
            input: []const f32,
            feedback_volume: f32,
            cutoff: f32,
        };

        delay: zang.Delay(DELAY_SAMPLES),
        filter: mod.Filter,

        pub fn init() @This() {
            return .{
                .delay = zang.Delay(DELAY_SAMPLES).init(),
                .filter = mod.Filter.init(),
            };
        }

        pub fn reset(self: *@This()) void {
            self.delay.reset();
        }

        pub fn paint(
            self: *@This(),
            span: zang.Span,
            outputs: [num_outputs][]f32,
            temps: [num_temps][]f32,
            note_id_changed: bool,
            params: Params,
        ) void {
            const output = outputs[0];
            const input = params.input;
            const temp0 = temps[0];
            const temp1 = temps[1];

            var start = span.start;
            const end = span.end;

            while (start < end) {
                // get delay buffer (this is the feedback)
                zang.zero(zang.Span.init(start, end), temp0);

                const samples_read = self.delay.readDelayBuffer(temp0[start..end]);

                const span1 = zang.Span.init(start, start + samples_read);

                // reduce its volume
                zang.multiplyWithScalar(span1, temp0, params.feedback_volume);

                // add input
                zang.addInto(span1, temp0, input);

                // filter it
                zang.zero(span1, temp1);
                self.filter.paint(span1, .{temp1}, .{}, note_id_changed, .{
                    .input = temp0,
                    .type = .low_pass,
                    .cutoff = zang.constant(params.cutoff),
                    .res = zang.constant(0.0),
                });

                // output it
                zang.addInto(span1, output, temp1);

                // also send what we have to the delay module (which doesn't
                // output anything)
                self.delay.writeDelayBuffer(temp1[span1.start..span1.end]);

                start += samples_read;
            }
        }
    };
}

pub fn StereoEchoes(comptime MAIN_DELAY: usize) type {
    const HALF_DELAY = MAIN_DELAY / 2;

    return struct {
        pub const num_outputs = 2;
        pub const num_temps = 4;
        pub const Params = struct {
            input: []const f32,
            feedback_volume: f32,
            cutoff: f32,
        };

        delay0: SimpleDelay(HALF_DELAY),
        delay1: SimpleDelay(HALF_DELAY),
        echoes: FilteredEchoes(MAIN_DELAY),

        pub fn init() @This() {
            return .{
                .delay0 = SimpleDelay(HALF_DELAY).init(),
                .delay1 = SimpleDelay(HALF_DELAY).init(),
                .echoes = FilteredEchoes(MAIN_DELAY).init(),
            };
        }

        pub fn reset(self: *@This()) void {
            self.delay0.reset();
            self.delay1.reset();
            self.echoes.reset();
        }

        pub fn paint(
            self: *@This(),
            span: zang.Span,
            outputs: [num_outputs][]f32,
            temps: [num_temps][]f32,
            note_id_changed: bool,
            params: Params,
        ) void {
            // output dry signal to center channel
            zang.addInto(span, outputs[0], params.input);
            zang.addInto(span, outputs[1], params.input);

            // initial half delay before first echo on the left channel
            zang.zero(span, temps[0]);
            self.delay0.paint(span, .{temps[0]}, .{}, note_id_changed, .{
                .input = params.input,
            });
            // filtered echoes to the left
            zang.zero(span, temps[1]);
            self.echoes.paint(span, .{temps[1]}, .{ temps[2], temps[3] }, note_id_changed, .{
                .input = temps[0],
                .feedback_volume = params.feedback_volume,
                .cutoff = params.cutoff,
            });
            // use another delay to mirror the left echoes to the right side
            zang.addInto(span, outputs[0], temps[1]);
            self.delay1.paint(span, .{outputs[1]}, .{}, note_id_changed, .{
                .input = temps[1],
            });
        }
    };
}
