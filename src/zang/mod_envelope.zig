const std = @import("std");
const Span = @import("basics.zig").Span;
const PaintCurve = @import("painter.zig").PaintCurve;
const PaintState = @import("painter.zig").PaintState;
const Painter = @import("painter.zig").Painter;

pub const Envelope = struct {
    pub const num_outputs = 1;
    pub const num_temps = 0;
    pub const Params = struct {
        sample_rate: f32,
        attack: PaintCurve,
        decay: PaintCurve,
        release: PaintCurve,
        sustain_volume: f32,
        note_on: bool,
    };

    const State = enum { idle, attack, decay, sustain, release };

    state: State,
    painter: Painter,

    pub fn init() Envelope {
        return .{
            .state = .idle,
            .painter = Painter.init(),
        };
    }

    fn changeState(self: *Envelope, new_state: State) void {
        self.state = new_state;
        self.painter.newCurve();
    }

    fn paintOn(self: *Envelope, buf: []f32, p: Params, new_note: bool) void {
        var ps = PaintState.init(buf, p.sample_rate);

        if (new_note) {
            self.changeState(.attack);
        }

        std.debug.assert(self.state != .release);

        // this condition can be hit by example_two.zig if you mash the keyboard
        if (self.state == .idle) {
            self.changeState(.attack);
        }

        if (self.state == .attack) {
            if (self.painter.paintToward(&ps, p.attack, 1.0)) {
                if (p.sustain_volume < 1.0) {
                    self.changeState(.decay);
                } else {
                    self.changeState(.sustain);
                }
            }
        }

        if (self.state == .decay) {
            if (self.painter.paintToward(&ps, p.decay, p.sustain_volume)) {
                self.changeState(.sustain);
            }
        }

        if (self.state == .sustain) {
            self.painter.paintFlat(&ps, p.sustain_volume);
        }

        std.debug.assert(ps.i == buf.len);
    }

    fn paintOff(self: *Envelope, buf: []f32, p: Params) void {
        if (self.state == .idle) {
            return;
        }

        var ps = PaintState.init(buf, p.sample_rate);

        if (self.state != .release) {
            self.changeState(.release);
        }

        if (self.painter.paintToward(&ps, p.release, 0.0)) {
            self.changeState(.idle);
        }
    }

    pub fn paint(
        self: *Envelope,
        span: Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        const output = outputs[0][span.start..span.end];

        if (params.note_on) {
            self.paintOn(output, params, note_id_changed);
        } else {
            self.paintOff(output, params);
        }
    }
};
