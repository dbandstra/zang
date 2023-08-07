// Painter:
// helper struct to paint a "direct current" style line that gradually moves
// toward a destination value. useful for things like envelope, portamento, or
// a low-frequency low-pass filter.

const Span = @import("basics.zig").Span;
const addScalarInto = @import("basics.zig").addScalarInto;

// this is a struct to be used temporarily within a single paint call.
// you initialize one, then pass it to paintFlat/paintToward.
pub const PaintState = struct {
    buf: []f32,
    i: usize,
    sample_rate: f32,

    pub inline fn init(buf: []f32, sample_rate: f32) PaintState {
        return .{
            .buf = buf,
            .i = 0,
            .sample_rate = sample_rate,
        };
    }
};

pub const PaintCurve = union(enum) {
    instantaneous,
    linear: f32, // duration (must be > 0)
    squared: f32, // ditto
    cubed: f32, // ditto
};

// this is a long-lived struct, which remembers progress between paints
pub const Painter = struct {
    t: f32,
    last_value: f32,
    start: f32,

    pub fn init() Painter {
        return .{
            .t = 0.0,
            .last_value = 0.0,
            .start = 0.0,
        };
    }

    // reset curve timer
    pub fn newCurve(self: *Painter) void {
        self.start = self.last_value;
        self.t = 0.0;
    }

    // paint a constant value until the end of the buffer
    pub fn paintFlat(self: *Painter, state: *PaintState, value: f32) void {
        _ = self;
        const buf = state.buf;
        addScalarInto(Span.init(state.i, buf.len), buf, value);
        state.i = buf.len;
    }

    // paint samples, approaching `goal` as we go. stop when we hit `goal` or
    // when we hit the end of the buffer, whichever comes first. return true
    // if we reached the `goal` before hitting the end of the buffer.
    pub fn paintToward(
        self: *Painter,
        state: *PaintState,
        curve: PaintCurve,
        goal: f32,
    ) bool {
        if (self.t >= 1.0) {
            return true;
        }

        var curve_func: enum { linear, squared, cubed } = undefined;
        var duration: f32 = undefined;
        switch (curve) {
            .instantaneous => {
                self.t = 1.0;
                self.last_value = goal;
                return true;
            },
            .linear => |dur| {
                curve_func = .linear;
                duration = dur;
            },
            .squared => |dur| {
                curve_func = .squared;
                duration = dur;
            },
            .cubed => |dur| {
                curve_func = .cubed;
                duration = dur;
            },
        }

        var i = state.i;

        const t_step = 1.0 / (duration * state.sample_rate);
        var finished = false;

        // TODO - this can be optimized
        const buf = state.buf;
        while (!finished and i < buf.len) : (i += 1) {
            self.t += t_step;
            if (self.t >= 1.0) {
                self.t = 1.0;
                finished = true;
            }
            const it = 1.0 - self.t;
            const tp = switch (curve_func) {
                .linear => self.t,
                .squared => 1.0 - it * it,
                .cubed => 1.0 - it * it * it,
            };
            self.last_value = self.start + tp * (goal - self.start);
            buf[i] += self.last_value;
        }

        state.i = i;
        return finished;
    }
};
