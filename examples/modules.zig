const zang = @import("zang");
const note_frequencies = @import("zang-12tet");

pub const PulseModOscillator = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 3;
    pub const Params = struct { freq: f32 };

    carrier: zang.Oscillator,
    modulator: zang.Oscillator,
    // ratio: the carrier oscillator will use whatever frequency you give the
    // PulseModOscillator. the modulator oscillator will multiply the frequency
    // by this ratio. for example, a ratio of 0.5 means that the modulator
    // oscillator will always play at half the frequency of the carrier
    // oscillator
    ratio: f32,
    // multiplier: the modulator oscillator's output is multiplied by this
    // before it is fed in to the phase input of the carrier oscillator.
    multiplier: f32,

    pub fn init(ratio: f32, multiplier: f32) PulseModOscillator {
        return PulseModOscillator {
            .carrier = zang.Oscillator.init(),
            .modulator = zang.Oscillator.init(),
            .ratio = ratio,
            .multiplier = multiplier,
        };
    }

    pub fn reset(self: *PulseModOscillator) void {
        self.carrier.reset();
        self.modulator.reset();
    }

    pub fn paint(self: *PulseModOscillator, sample_rate: f32, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        const out = outputs[0];

        zang.set(temps[0], params.freq);
        zang.set(temps[1], params.freq * self.ratio);
        zang.zero(temps[2]);
        self.modulator.paint(sample_rate, [1][]f32{temps[2]}, [0][]f32{}, zang.Oscillator.Params {
            .waveform = .Sine,
            .freq = zang.buffer(temps[1]),
            .phase = zang.constant(0.0),
            .colour = 0.5,
        });
        zang.zero(temps[1]);
        zang.multiplyScalar(temps[1], temps[2], self.multiplier);
        self.carrier.paint(sample_rate, [1][]f32{out}, [0][]f32{}, zang.Oscillator.Params {
            .waveform = .Sine,
            .freq = zang.buffer(temps[0]),
            .phase = zang.buffer(temps[1]),
            .colour = 0.5,
        });
    }
};

// PulseModOscillator packaged with an envelope
pub const PMOscInstrument = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 4;
    pub const Params = struct { freq: f32, note_on: bool };

    osc: PulseModOscillator,
    env: zang.Envelope,

    pub fn init(release_duration: f32) PMOscInstrument {
        return PMOscInstrument {
            .osc = PulseModOscillator.init(1.0, 1.5),
            .env = zang.Envelope.init(zang.EnvParams {
                .attack_duration = 0.025,
                .decay_duration = 0.1,
                .sustain_volume = 0.5,
                .release_duration = release_duration,
            }),
        };
    }

    pub fn reset(self: *PMOscInstrument) void {
        self.osc.reset();
        self.env.reset();
    }

    pub fn paint(self: *PMOscInstrument, sample_rate: f32, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        zang.zero(temps[0]);
        self.osc.paint(sample_rate, [1][]f32{temps[0]}, [3][]f32{temps[1], temps[2], temps[3]}, PulseModOscillator.Params {
            .freq = params.freq,
        });
        zang.zero(temps[1]);
        self.env.paint(sample_rate, [1][]f32{temps[1]}, [0][]f32{}, zang.Envelope.Params {
            .note_on = params.note_on,
        });
        zang.multiply(outputs[0], temps[0], temps[1]);
    }
};

pub const FilteredSawtoothInstrument = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 4;
    pub const Params = struct { freq: f32, note_on: bool };

    osc: zang.Oscillator,
    env: zang.Envelope,
    flt: zang.Filter,

    pub fn init() FilteredSawtoothInstrument {
        return FilteredSawtoothInstrument {
            .osc = zang.Oscillator.init(),
            .env = zang.Envelope.init(zang.EnvParams {
                .attack_duration = 0.025,
                .decay_duration = 0.1,
                .sustain_volume = 0.5,
                .release_duration = 1.0,
            }),
            .flt = zang.Filter.init(),
        };
    }

    pub fn reset(self: *FilteredSawtoothInstrument) void {
        self.osc.reset();
        self.env.reset();
        self.flt.reset();
    }

    pub fn paint(self: *FilteredSawtoothInstrument, sample_rate: f32, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        zang.zero(temps[3]);
        self.osc.paint(sample_rate, [1][]f32{temps[3]}, [0][]f32{}, zang.Oscillator.Params {
            .waveform = .Sawtooth,
            .freq = zang.constant(params.freq),
            .phase = zang.constant(0.0),
            .colour = 0.5,
        });
        zang.zero(temps[0]);
        zang.multiplyScalar(temps[0], temps[3], 2.5); // boost sawtooth volume
        zang.zero(temps[1]);
        self.env.paint(sample_rate, [1][]f32{temps[1]}, [0][]f32{}, zang.Envelope.Params {
            .note_on = params.note_on,
        });
        zang.zero(temps[2]);
        zang.multiply(temps[2], temps[0], temps[1]);
        self.flt.paint(sample_rate, [1][]f32{outputs[0]}, [0][]f32{}, zang.Filter.Params {
            .input = temps[2],
            .filterType = .LowPass,
            .cutoff = zang.constant(zang.cutoffFromFrequency(440.0 * note_frequencies.C5, sample_rate)),
            .resonance = 0.7,
        });
    }
};

pub const NiceInstrument = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 2;
    pub const Params = struct { freq: f32, note_on: bool };

    osc: zang.PulseOsc,
    flt: zang.Filter,
    env: zang.Envelope,

    pub fn init() NiceInstrument {
        return NiceInstrument {
            .osc = zang.PulseOsc.init(),
            .flt = zang.Filter.init(),
            .env = zang.Envelope.init(zang.EnvParams {
                .attack_duration = 0.01,
                .decay_duration = 0.1,
                .sustain_volume = 0.8,
                .release_duration = 0.5,
            }),
        };
    }

    pub fn reset(self: *NiceInstrument) void {
        self.osc.reset();
        self.flt.reset();
        self.env.reset();
    }

    pub fn paint(self: *NiceInstrument, sample_rate: f32, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        zang.zero(temps[0]);
        self.osc.paint(sample_rate, [1][]f32{temps[0]}, [0][]f32{}, zang.PulseOsc.Params {
            .freq = params.freq,
            .colour = 0.3,
        });
        zang.multiplyWithScalar(temps[0], 0.5);
        zang.zero(temps[1]);
        self.flt.paint(sample_rate, [1][]f32{temps[1]}, [0][]f32{}, zang.Filter.Params {
            .input = temps[0],
            .filterType = .LowPass,
            .cutoff = zang.constant(zang.cutoffFromFrequency(params.freq * 8.0, sample_rate)),
            .resonance = 0.7,
        });
        zang.zero(temps[0]);
        self.env.paint(sample_rate, [1][]f32{temps[0]}, [0][]f32{}, zang.Envelope.Params {
            .note_on = params.note_on,
        });
        zang.multiply(outputs[0], temps[0], temps[1]);
    }
};

pub const HardSquareInstrument = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 2;
    pub const Params = struct { freq: f32, note_on: bool };

    osc: zang.PulseOsc,
    gate: zang.Gate,

    pub fn init() HardSquareInstrument {
        return HardSquareInstrument {
            .osc = zang.PulseOsc.init(),
            .gate = zang.Gate.init(),
        };
    }

    pub fn reset(self: *HardSquareInstrument) void {
        self.osc.reset();
        self.gate.reset();
    }

    pub fn paint(self: *HardSquareInstrument, sample_rate: f32, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        zang.zero(temps[0]);
        self.osc.paint(sample_rate, [1][]f32{temps[0]}, [0][]f32{}, zang.PulseOsc.Params {
            .freq = params.freq,
            .colour = 0.5,
        });
        zang.zero(temps[1]);
        self.gate.paint(sample_rate, [1][]f32{temps[1]}, [0][]f32{}, zang.Gate.Params {
            .note_on = params.note_on,
        });
        zang.multiply(outputs[0], temps[0], temps[1]);
    }
};