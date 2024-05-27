// filter implementation ripped from farbrausch's v2 (public domain)
// https://github.com/farbrausch/fr_public/blob/master/v2/LICENSE.txt
// https://github.com/farbrausch/fr_public/blob/master/v2/synth_core.cpp

const std = @import("std");
const zang = @import("zang");

const fcdcoffset: f32 = 3.814697265625e-6; // 2^-18

pub const Type = enum {
    bypass,
    low_pass,
    band_pass,
    high_pass,
    notch,
    all_pass,
};

// convert a frequency into a cutoff value so it can be used with the filter
pub fn cutoffFromFrequency(frequency: f32, sample_rate: f32) f32 {
    const v = 2.0 * (1.0 - std.math.cos(std.math.pi * frequency / sample_rate));
    return std.math.sqrt(std.math.clamp(v, 0.0, 1.0));
}

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    input: []const f32,
    type: Type,
    cutoff: zang.ConstantOrBuffer, // 0-1
    res: zang.ConstantOrBuffer, // 0-1
};

l: f32,
b: f32,

pub fn init() @This() {
    return .{
        .l = 0.0,
        .b = 0.0,
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
    _ = temps;
    _ = note_id_changed;

    const output = outputs[0][span.start..span.end];
    const input = params.input[span.start..span.end];

    switch (params.cutoff) {
        .constant => |cutoff| {
            switch (params.res) {
                .constant => |res| paintFunction(self, output, input, params.type, true, cutoff, undefined, true, res, undefined),
                .buffer => |res| paintFunction(self, output, input, params.type, true, cutoff, undefined, false, undefined, res[span.start..span.end]),
            }
        },
        .buffer => |cutoff| {
            switch (params.res) {
                .constant => |res| paintFunction(self, output, input, params.type, false, undefined, cutoff[span.start..span.end], true, res, undefined),
                .buffer => |res| paintFunction(self, output, input, params.type, false, undefined, cutoff[span.start..span.end], false, undefined, res[span.start..span.end]),
            }
        },
    }
}

fn paintFunction(
    self: *@This(),
    output: []f32,
    input: []const f32,
    filter_type: Type,
    comptime cutoff_is_constant: bool,
    cutoff_constant: f32,
    cutoff_buffer: []const f32,
    comptime res_is_constant: bool,
    res_constant: f32,
    res_buffer: []const f32,
) void {
    var l_mul: f32 = 0.0;
    var b_mul: f32 = 0.0;
    var h_mul: f32 = 0.0;

    switch (filter_type) {
        .bypass => {
            var i: usize = 0;
            while (i < output.len) : (i += 1) {
                output[i] += input[i];
            }
            return;
        },
        .low_pass => l_mul = 1.0,
        .band_pass => b_mul = 1.0,
        .high_pass => h_mul = 1.0,
        .notch => {
            l_mul = 1.0;
            h_mul = 1.0;
        },
        .all_pass => {
            l_mul = 1.0;
            b_mul = 1.0;
            h_mul = 1.0;
        },
    }

    var cut: f32 = undefined;
    if (cutoff_is_constant)
        cut = std.math.clamp(cutoff_constant, 0.0, 1.0);

    var res: f32 = undefined;
    if (res_is_constant)
        res = 1.0 - std.math.clamp(res_constant, 0.0, 1.0);

    var l = self.l;
    var b = self.b;

    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        if (!cutoff_is_constant)
            cut = std.math.clamp(cutoff_buffer[i], 0.0, 1.0);
        if (!res_is_constant)
            res = 1.0 - std.math.clamp(res_buffer[i], 0.0, 1.0);

        // run 2x oversampled step

        // the filters get slightly biased inputs to avoid the state variables
        // getting too close to 0 for prolonged periods of time (which would
        // cause denormals to appear)
        const in = input[i] + fcdcoffset;

        // step 1
        l += cut * b - fcdcoffset; // undo bias here (1 sample delay)
        b += cut * (in - b * res - l);

        // step 2
        l += cut * b;
        const h = in - b * res - l;
        b += cut * h;

        output[i] += l * l_mul + b * b_mul + h * h_mul;
    }

    self.l = l;
    self.b = b;
}
