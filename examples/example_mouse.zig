const zang = @import("zang");
const mod = @import("modules");
const common = @import("common.zig");
const c = @import("common/c.zig");
const PhaseModOscillator = @import("modules.zig").PhaseModOscillator;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_mouse
    \\
    \\Play a phase-modulation instrument with the keyboard,
    \\while controlling the sound parameters with the mouse
    \\position.
    \\
    \\Press spacebar to toggle between relative (the
    \\default) and absolute modulator frequency.
;

const a4 = 440.0;

const PMOscInstrument = struct {
    pub const num_outputs = 1;
    pub const num_temps = 3;
    pub const Params = struct {
        sample_rate: f32,
        freq: f32,
        note_on: bool,
        relative: bool,
        ratio: []const f32,
        multiplier: []const f32,
    };

    osc: PhaseModOscillator,
    env: mod.Envelope,

    pub fn init() PMOscInstrument {
        return .{
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
            .relative = params.relative,
            .ratio = zang.buffer(params.ratio),
            .multiplier = zang.buffer(params.multiplier),
        });
        zang.zero(span, temps[1]);
        self.env.paint(span, .{temps[1]}, .{}, note_id_changed, .{
            .sample_rate = params.sample_rate,
            .attack = .{ .cubed = 0.025 },
            .decay = .{ .cubed = 0.1 },
            .release = .{ .cubed = 1.0 },
            .sustain_volume = 0.5,
            .note_on = params.note_on,
        });
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 5;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    const Instr = struct {
        const Params = struct { freq: f32, note_on: bool };

        iq: zang.Notes(Params).ImpulseQueue,
        idgen: zang.IdGenerator,
        mod: PMOscInstrument,
        trig: zang.Trigger(Params),
    };

    const Porta = struct {
        const Params = struct { value: f32, note_on: bool };

        iq: zang.Notes(Params).ImpulseQueue,
        idgen: zang.IdGenerator,

        mod: mod.Portamento,
        trig: zang.Trigger(Params),
    };

    key: ?i32,
    first: bool,
    mode: u32,
    mode_iq: zang.Notes(u32).ImpulseQueue,
    mode_idgen: zang.IdGenerator,
    instr: Instr,
    ratio: Porta,
    multiplier: Porta,

    pub fn init() MainModule {
        return .{
            .key = null,
            .first = true,
            .mode = 0,
            .mode_iq = zang.Notes(u32).ImpulseQueue.init(),
            .mode_idgen = zang.IdGenerator.init(),
            .instr = .{
                .iq = zang.Notes(Instr.Params).ImpulseQueue.init(),
                .idgen = zang.IdGenerator.init(),
                .mod = PMOscInstrument.init(),
                .trig = zang.Trigger(Instr.Params).init(),
            },
            .ratio = .{
                .iq = zang.Notes(Porta.Params).ImpulseQueue.init(),
                .idgen = zang.IdGenerator.init(),
                .mod = mod.Portamento.init(),
                .trig = zang.Trigger(Porta.Params).init(),
            },
            .multiplier = .{
                .iq = zang.Notes(Porta.Params).ImpulseQueue.init(),
                .idgen = zang.IdGenerator.init(),
                .mod = mod.Portamento.init(),
                .trig = zang.Trigger(Porta.Params).init(),
            },
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
            self.mode_iq.push(0, self.mode_idgen.nextId(), self.mode);
        }
        // ratio
        zang.zero(span, temps[0]);
        {
            var ctr = self.ratio.trig.counter(span, self.ratio.iq.consume());
            while (self.ratio.trig.next(&ctr)) |result| {
                self.ratio.mod.paint(
                    result.span,
                    .{temps[0]},
                    .{},
                    result.note_id_changed,
                    .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .curve = .{ .linear = 0.1 },
                        .goal = switch (self.mode) {
                            0 => result.params.value * 4.0,
                            else => result.params.value * 880.0,
                        },
                        .note_on = result.params.note_on,
                        .prev_note_on = true,
                    },
                );
            }
        }
        // multiplier
        zang.zero(span, temps[1]);
        {
            const iap = self.multiplier.iq.consume();
            var ctr = self.multiplier.trig.counter(span, iap);
            while (self.multiplier.trig.next(&ctr)) |result| {
                self.multiplier.mod.paint(
                    result.span,
                    .{temps[1]},
                    .{},
                    result.note_id_changed,
                    .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .curve = .{ .linear = 0.1 },
                        .goal = result.params.value * 2.0,
                        .note_on = result.params.note_on,
                        .prev_note_on = true,
                    },
                );
            }
        }
        // instr
        {
            var ctr = self.instr.trig.counter(span, self.instr.iq.consume());
            while (self.instr.trig.next(&ctr)) |result| {
                self.instr.mod.paint(
                    result.span,
                    outputs,
                    .{ temps[2], temps[3], temps[4] },
                    result.note_id_changed,
                    .{
                        .sample_rate = AUDIO_SAMPLE_RATE,
                        .freq = result.params.freq,
                        .note_on = result.params.note_on,
                        .relative = self.mode == 0,
                        .ratio = temps[0],
                        .multiplier = temps[1],
                    },
                );
            }
        }
    }

    pub fn mouseEvent(
        self: *MainModule,
        x: f32,
        y: f32,
        impulse_frame: usize,
    ) void {
        self.ratio.iq.push(impulse_frame, self.ratio.idgen.nextId(), .{
            .value = x,
            .note_on = true,
        });
        self.multiplier.iq.push(impulse_frame, self.multiplier.idgen.nextId(), .{
            .value = y,
            .note_on = true,
        });
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (key == c.SDLK_SPACE and down) {
            self.mode = (self.mode + 1) % 2;
            self.mode_iq.push(impulse_frame, self.mode_idgen.nextId(), self.mode);
            return false;
        }
        if (common.getKeyRelFreq(key)) |rel_freq| {
            if (down or (if (self.key) |nh| nh == key else false)) {
                self.key = if (down) key else null;
                self.instr.iq.push(impulse_frame, self.instr.idgen.nextId(), .{
                    .freq = a4 * rel_freq,
                    .note_on = down,
                });
            }
        }
        return true;
    }
};
