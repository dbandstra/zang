// Cycle: return a value that goes from 0 to 0.9999999 and wraps back to 0.
// if `speed` is 1, it will cycle once per second.

const std = @import("std");
const zang = @import("../zang.zig");

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    sample_rate: f32,
    speed: zang.ConstantOrBuffer,
};

t: f32,

pub fn init() @This() {
    return .{
        .t = 0,
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
    // TODO it should be possible to optimize the loop by pre-calculating
    // how many iterations you should be able to do without truncating
    switch (params.speed) {
        .constant => |speed| {
            const step = speed / params.sample_rate;
            var t = self.t;
            var i = span.start;
            while (i < span.end) : (i += 1) {
                outputs[0][i] += t;
                t += step;
                t -= std.math.trunc(t);
            }
            self.t = t;
        },
        .buffer => |speed| {
            const isr = 1.0 / params.sample_rate;
            var t = self.t;
            var i = span.start;
            while (i < span.end) : (i += 1) {
                outputs[0][i] += t;
                t += speed[i] * isr;
                t -= std.math.trunc(t);
            }
            self.t = t;
        },
    }
}
