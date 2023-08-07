// implementation ripped from farbrausch's v2 (public domain)
// https://github.com/farbrausch/fr_public/blob/master/v2/LICENSE.txt
// https://github.com/farbrausch/fr_public/blob/master/v2/synth_core.cpp

const std = @import("std");
const zang = @import("zang");

const fc32bit: f32 = 1 << 32;

inline fn sqr(v: f32) f32 {
    return v * v;
}

inline fn clamp01(v: f32) f32 {
    return if (v < 0.0) 0.0 else if (v > 1.0) 1.0 else v;
}

// 32-bit value into float with 23 bits precision
inline fn utof23(x: u32) f32 {
    return @as(f32, @bitCast((x >> 9) | 0x3f800000)) - 1;
}

// float from [0,1) into 0.32 unsigned fixed-point
inline fn ftou32(v: f32) u32 {
    return @intFromFloat(v * fc32bit * 0.99995);
}

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    sample_rate: f32,
    freq: zang.ConstantOrBuffer,
    color: f32,
};

cnt: u32,
t: f32, // TODO - remove (see below)

pub fn init() @This() {
    return .{
        .cnt = 0,
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
    _ = temps;
    _ = note_id_changed;

    switch (params.freq) {
        .constant => |freq| {
            self.paintConstantFrequency(
                outputs[0][span.start..span.end],
                params.sample_rate,
                freq,
                params.color,
            );
        },
        .buffer => |freq| {
            self.paintControlledFrequency(
                outputs[0][span.start..span.end],
                params.sample_rate,
                freq[span.start..span.end],
                params.color,
            );
        },
    }
}

fn paintConstantFrequency(
    self: *@This(),
    output: []f32,
    sample_rate: f32,
    freq: f32,
    color: f32,
) void {
    if (freq < 0 or freq > sample_rate / 8.0) {
        return;
    }
    // note: farbrausch code includes some explanatory comments. i've
    // preserved the variable names they used, but condensed the code
    var cnt = self.cnt;
    const SRfcobasefrq = fc32bit / sample_rate;
    const ifreq: u32 = @intFromFloat(SRfcobasefrq * freq);
    const brpt = ftou32(clamp01(color));
    const gain = 0.7;
    const f = utof23(ifreq);
    const omf = 1.0 - f;
    const rcpf = 1.0 / f;
    const col = utof23(brpt);
    const c1 = gain / col;
    const c2 = -gain / (1.0 - col);
    var state = if ((cnt -% ifreq) < brpt) @as(u32, 3) else @as(u32, 0);
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        const p = utof23(cnt) - col;
        state = ((state << 1) | @intFromBool(cnt < brpt)) & 3;
        const s = state | (@as(u32, @intFromBool(cnt < ifreq)) << 2);
        output[i] += gain + switch (s) {
            0b011 => c1 * (p + p - f), // up
            0b000 => c2 * (p + p - f), // down
            0b010 => rcpf * (c2 * sqr(p) - c1 * sqr(p - f)), // up down
            0b101 => -rcpf * (gain + c2 * sqr(p + omf) - c1 * sqr(p)), // down up
            0b111 => -rcpf * (gain + c1 * omf * (p + p + omf)), // up down up
            0b100 => -rcpf * (gain + c2 * omf * (p + p + omf)), // down up down
            else => unreachable,
        };
        cnt +%= ifreq;
    }
    self.cnt = cnt;
}

fn paintControlledFrequency(
    self: *@This(),
    output: []f32,
    sample_rate: f32,
    freq: []const f32,
    color: f32,
) void {
    // TODO - implement color properly
    // TODO - rewrite using self.cnt and get rid of self.t
    // TODO - antialiasing
    // TODO - add equivalent of the bad frequency check at the top of
    // paintConstantFrequency
    var t = self.t;
    const gain = 0.7;
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        var frac: f32 = undefined;
        if (color < 0.25 or color > 0.75) {
            // sawtooth
            frac = (t - std.math.floor(t)) * 2.0 - 1.0;
        } else {
            // triangle
            frac = t - std.math.floor(t);
            if (frac < 0.25) {
                frac = frac * 4.0;
            } else if (frac < 0.75) {
                frac = 1.0 - (frac - 0.25) * 4.0;
            } else {
                frac = (frac - 0.75) * 4.0 - 1.0;
            }
        }
        output[i] += gain * frac;
        t += freq[i] / sample_rate;
    }
    // it actually goes out of tune without this!...
    self.t = t - std.math.trunc(t);
}
