const std = @import("std");
const zang = @import("zang");

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    sample_rate: f32,
    attack: zang.PaintCurve,
    decay: zang.PaintCurve,
    release: zang.PaintCurve,
    sustain_volume: f32,
    note_on: bool,
};

const State = enum {
    idle,
    attack,
    decay,
    sustain,
    release,
};

state: State,
painter: zang.Painter,

pub fn init() @This() {
    return .{
        .state = .idle,
        .painter = zang.Painter.init(),
    };
}

fn changeState(self: *@This(), new_state: State) void {
    self.state = new_state;
    self.painter.newCurve();
}

fn paintOn(self: *@This(), buf: []f32, p: Params, new_note: bool) void {
    var ps = zang.PaintState.init(buf, p.sample_rate);

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

// if note_on is false: set state to "release", paint towards 0, and when we
// get there, set state to "idle".
fn paintOff(self: *@This(), buf: []f32, p: Params) void {
    if (self.state == .idle) {
        return;
    }

    if (self.state != .release) {
        self.changeState(.release);
    }

    var ps = zang.PaintState.init(buf, p.sample_rate);
    if (self.painter.paintToward(&ps, p.release, 0.0)) {
        self.changeState(.idle);
    }
}

pub fn paint(
    self: *@This(),
    span: zang.Span,
    outputs: [num_outputs][]f32,
    temps: [num_temps][]f32,
    note_id_changed: bool,
    params: Params,
) void {
    _ = temps;

    const output = outputs[0][span.start..span.end];

    if (params.note_on) {
        self.paintOn(output, params, note_id_changed);
    } else {
        self.paintOff(output, params);
    }
}
