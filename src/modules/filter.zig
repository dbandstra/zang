// filter implementation ripped from farbrausch's v2 (public domain)
// https://github.com/farbrausch/fr_public/blob/master/v2/LICENSE.txt
// https://github.com/farbrausch/fr_public/blob/master/v2/synth_core.cpp

const std = @import("std");
const zang = @import("../zang.zig");

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
    var v: f32 = undefined;
    v = 2.0 * (1.0 - std.math.cos(std.math.pi * frequency / sample_rate));
    v = std.math.max(0.0, std.math.min(1.0, v));
    v = std.math.sqrt(v);
    return v;
}

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    input: []const f32,
    type: Type,
    cutoff: zang.ConstantOrBuffer, // 0-1
    res: f32, // 0-1
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
    // TODO make res a ConstantOrBuffer as well
    const output = outputs[0][span.start..span.end];
    const input = params.input[span.start..span.end];

    switch (params.cutoff) {
        .constant => |cutoff| {
            self.paintSimple(
                output,
                input,
                params.type,
                cutoff,
                params.res,
            );
        },
        .buffer => |cutoff| {
            self.paintControlledCutoff(
                output,
                input,
                params.type,
                cutoff[span.start..span.end],
                params.res,
            );
        },
    }
}

fn paintSimple(
    self: *@This(),
    buf: []f32,
    input: []const f32,
    filter_type: Type,
    cutoff: f32,
    resonance: f32,
) void {
    var l_mul: f32 = 0.0;
    var b_mul: f32 = 0.0;
    var h_mul: f32 = 0.0;

    switch (filter_type) {
        .bypass => {
            std.mem.copy(f32, buf, input);
            return;
        },
        .low_pass => {
            l_mul = 1.0;
        },
        .band_pass => {
            b_mul = 1.0;
        },
        .high_pass => {
            h_mul = 1.0;
        },
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

    var i: usize = 0;

    const cut = std.math.max(0.0, std.math.min(1.0, cutoff));
    const res = 1.0 - std.math.max(0.0, std.math.min(1.0, resonance));

    var l = self.l;
    var b = self.b;
    var h: f32 = undefined;

    while (i < buf.len) : (i += 1) {
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
        h = in - b * res - l;
        b += cut * h;

        buf[i] += l * l_mul + b * b_mul + h * h_mul;
    }

    self.l = l;
    self.b = b;
}

fn paintControlledCutoff(
    self: *@This(),
    buf: []f32,
    input: []const f32,
    filter_type: Type,
    input_cutoff: []const f32,
    resonance: f32,
) void {
    std.debug.assert(buf.len == input.len);

    var l_mul: f32 = 0.0;
    var b_mul: f32 = 0.0;
    var h_mul: f32 = 0.0;

    switch (filter_type) {
        .bypass => {
            std.mem.copy(f32, buf, input);
            return;
        },
        .low_pass => {
            l_mul = 1.0;
        },
        .band_pass => {
            b_mul = 1.0;
        },
        .high_pass => {
            h_mul = 1.0;
        },
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

    var i: usize = 0;

    const res = 1.0 - std.math.max(0.0, std.math.min(1.0, resonance));

    var l = self.l;
    var b = self.b;
    var h: f32 = undefined;

    while (i < buf.len) : (i += 1) {
        const cutoff = std.math.max(0.0, std.math.min(1.0, input_cutoff[i]));

        // run 2x oversampled step

        // the filters get slightly biased inputs to avoid the state variables
        // getting too close to 0 for prolonged periods of time (which would
        // cause denormals to appear)
        const in = input[i] + fcdcoffset;

        // step 1
        l += cutoff * b - fcdcoffset; // undo bias here (1 sample delay)
        b += cutoff * (in - b * res - l);

        // step 2
        l += cutoff * b;
        h = in - b * res - l;
        b += cutoff * h;

        buf[i] += l * l_mul + b * b_mul + h * h_mul;
    }

    self.l = l;
    self.b = b;
}
