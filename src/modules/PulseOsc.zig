// implementation ripped from farbrausch's v2 (public domain)
// https://github.com/farbrausch/fr_public/blob/master/v2/LICENSE.txt
// https://github.com/farbrausch/fr_public/blob/master/v2/synth_core.cpp

// this is a higher quality version of the square wave oscillator in
// mod_oscillator.zig. it deals with aliasing by computing an average value for
// each sample. however it doesn't support sweeping the input params (frequency
// etc.)

const zang = @import("zang");

const fc32bit: f32 = 1 << 32;

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

pub fn init() @This() {
    return .{
        .cnt = 0,
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
    const gdf = gain / utof23(ifreq);
    const col = utof23(brpt);
    const cc121 = gdf * 2.0 * (col - 1.0) + gain;
    const cc212 = gdf * 2.0 * col - gain;
    var state = if ((cnt -% ifreq) < brpt) @as(u32, 0b011) else @as(u32, 0b000);
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        const p = utof23(cnt);
        state = ((state << 1) | @intFromBool(cnt < brpt)) & 3;
        const transition = state | (@as(u32, @intFromBool(cnt < ifreq)) << 2);
        output[i] += switch (transition) {
            0b011 => gain, // up
            0b000 => -gain, // down
            0b010 => gdf * 2.0 * (col - p) + gain, // up down
            0b101 => gdf * 2.0 * p - gain, // down up
            0b111 => cc121, // up down up
            0b100 => cc212, // down up down
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
    // same as above but with more stuff moved into the loop.
    // farbrausch's code didn't support controlled frequency. hope i got it
    // right.
    var cnt = self.cnt;

    const SRfcobasefrq = fc32bit / sample_rate;
    const brpt = ftou32(clamp01(color));
    const gain = 0.7;
    const col = utof23(brpt);

    for (freq, 0..) |s_freq, i| {
        if (s_freq < 0 or s_freq > sample_rate / 8.0)
            continue;
        const ifreq: u32 = @intFromFloat(SRfcobasefrq * s_freq);
        const gdf = gain / utof23(ifreq);
        const cc121 = gdf * 2.0 * (col - 1.0) + gain;
        const cc212 = gdf * 2.0 * col - gain;
        const p = utof23(cnt);
        const c: u32 = @intFromBool((cnt -% ifreq) < brpt);
        const state: u32 = @intFromBool(cnt < brpt) | (c << 1);
        const transition = state | (@as(u32, @intFromBool(cnt < ifreq)) << 2);
        output[i] += switch (transition) {
            0b011 => gain, // up
            0b000 => -gain, // down
            0b010 => gdf * 2.0 * (col - p) + gain, // up down
            0b101 => gdf * 2.0 * p - gain, // down up
            0b111 => cc121, // up down up
            0b100 => cc212, // down up down
            else => unreachable,
        };
        cnt +%= ifreq;
    }

    self.cnt = cnt;
}
