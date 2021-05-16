const std = @import("std");
const zang = @import("../zang.zig");

inline fn sin(t: f32) f32 {
    return std.math.sin(t * std.math.pi * 2.0);
}

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    sample_rate: f32,
    freq: zang.ConstantOrBuffer,
    phase: zang.ConstantOrBuffer,
};

t: f32,

pub fn init() @This() {
    return .{
        .t = 0.0,
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
    var i: usize = 0;

    var t = self.t;
    // it actually goes out of tune without this!...
    defer self.t = t - std.math.trunc(t);

    switch (params.freq) {
        .constant => |freq| {
            const t_step = freq / params.sample_rate;

            switch (params.phase) {
                .constant => |phase| {
                    // constant frequency, constant phase
                    while (i < output.len) : (i += 1) {
                        output[i] += sin(t + phase);
                        t += t_step;
                    }
                },
                .buffer => |phase| {
                    // constant frequency, controlled phase
                    const phase_slice = phase[span.start..span.end];
                    while (i < output.len) : (i += 1) {
                        output[i] += sin(t + phase_slice[i]);
                        t += t_step;
                    }
                },
            }
        },
        .buffer => |freq| {
            const freq_slice = freq[span.start..span.end];
            const inv_sample_rate = 1.0 / params.sample_rate;

            switch (params.phase) {
                .constant => |phase| {
                    // controlled frequency, constant phase
                    while (i < output.len) : (i += 1) {
                        output[i] += sin(t + phase);
                        t += freq_slice[i] * inv_sample_rate;
                    }
                },
                .buffer => |phase| {
                    // controlled frequency, controlled phase
                    const phase_slice = phase[span.start..span.end];
                    while (i < output.len) : (i += 1) {
                        output[i] += sin(t + phase_slice[i]);
                        t += freq_slice[i] * inv_sample_rate;
                    }
                },
            }
        },
    }
}
