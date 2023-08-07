const std = @import("std");
const zang = @import("zang");

// FIXME - no effort at all has been made to optimize the sampler module
// FIXME - use a better resampling filter
// TODO - more complex looping schemes
// TODO - allow sample_rate to be controlled

pub const Format = enum {
    unsigned8,
    signed16_lsb,
    signed24_lsb,
    signed32_lsb,
};

pub const Sample = struct {
    num_channels: usize,
    sample_rate: usize,
    format: Format,
    data: []const u8,
};

fn decodeSigned(
    comptime byte_count: u16,
    slice: []const u8,
    index: usize,
) f32 {
    const T = std.meta.Int(.signed, byte_count * 8);
    const subslice = slice[index * byte_count .. (index + 1) * byte_count];
    const sval = std.mem.readIntSliceLittle(T, subslice);
    const max = 1 << @as(u32, byte_count * 8 - 1);
    return @as(f32, @floatFromInt(sval)) / @as(f32, @floatFromInt(max));
}

fn getSample(params: Params, index1: i32) f32 {
    const bytes_per_sample: usize = switch (params.sample.format) {
        .unsigned8 => 1,
        .signed16_lsb => 2,
        .signed24_lsb => 3,
        .signed32_lsb => 4,
    };
    const num_samples: i32 = @intCast(params.sample.data.len / bytes_per_sample / params.sample.num_channels);
    const index = if (params.loop) @mod(index1, num_samples) else index1;

    if (index >= 0 and index < num_samples) {
        const i = @as(usize, @intCast(index)) * params.sample.num_channels +
            params.channel;

        return switch (params.sample.format) {
            .unsigned8 => (@as(f32, @floatFromInt(params.sample.data[i])) - 127.5) / 127.5,
            .signed16_lsb => decodeSigned(2, params.sample.data, i),
            .signed24_lsb => decodeSigned(3, params.sample.data, i),
            .signed32_lsb => decodeSigned(4, params.sample.data, i),
        };
    } else {
        return 0.0;
    }
}

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    sample_rate: f32,
    sample: Sample,
    channel: usize,
    loop: bool,
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
    _ = temps;

    if (params.channel >= params.sample.num_channels) {
        return;
    }

    if (note_id_changed) {
        self.t = 0.0;
    }

    const out = outputs[0][span.start..span.end];

    const ratio = @as(f32, @floatFromInt(params.sample.sample_rate)) / params.sample_rate;

    if (ratio < 0.0 and !params.loop) {
        // i don't think it makes sense to play backwards without looping
        return;
    }

    // FIXME - pulled these epsilon values out of my ass
    if (ratio > 0.9999 and ratio < 1.0001) {
        // no resampling needed
        const t: i32 = @intFromFloat(std.math.round(self.t));

        var i: u31 = 0;
        while (i < out.len) : (i += 1) {
            out[i] += getSample(params, t + @as(i32, i));
        }

        self.t += @as(f32, @floatFromInt(out.len));
    } else {
        // resample
        var i: u31 = 0;
        while (i < out.len) : (i += 1) {
            const t0: i32 = @intFromFloat(std.math.floor(self.t));
            const t1 = t0 + 1;
            const tfrac = @as(f32, @floatFromInt(t1)) - self.t;

            const s0 = getSample(params, t0);
            const s1 = getSample(params, t1);
            const s = s0 * (1.0 - tfrac) + s1 * tfrac;

            out[i] += s;

            self.t += ratio;
        }
    }

    if (self.t >= @as(f32, @floatFromInt(params.sample.data.len)) and params.loop) {
        self.t -= @as(f32, @floatFromInt(params.sample.data.len));
    }
}
