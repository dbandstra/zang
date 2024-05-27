const std = @import("std");

pub const AudioFormat = enum {
    signed8,
    signed16_lsb,
};

pub fn mixDown(
    dst: []u8,
    mix_buffer: []const f32,
    audio_format: AudioFormat,
    num_channels: usize,
    channel_index: usize,
    vol: f32,
) void {
    switch (audio_format) {
        .signed8 => {
            mixDownS8(dst, mix_buffer, num_channels, channel_index, vol);
        },
        .signed16_lsb => {
            mixDownS16LSB(dst, mix_buffer, num_channels, channel_index, vol);
        },
    }
}

// convert from float to 16-bit, applying clamping
// `vol` should be set to something lower than 1.0 to avoid clipping
fn mixDownS16LSB(
    dst: []u8,
    mix_buffer: []const f32,
    num_channels: usize,
    channel_index: usize,
    vol: f32,
) void {
    std.debug.assert(dst.len == mix_buffer.len * 2 * num_channels);

    const mul = vol * 32767.0;

    var i: usize = 0;
    while (i < mix_buffer.len) : (i += 1) {
        const value = mix_buffer[i] * mul;

        const clamped_value =
            if (value <= -32767.0)
            @as(i16, -32767)
        else if (value >= 32766.0)
            @as(i16, 32766)
        else if (value != value) // NaN
            @as(i16, 0)
        else
            @as(i16, @intFromFloat(value));

        const index = (i * num_channels + channel_index) * 2;
        dst[index + 0] = @intCast(clamped_value & 0xFF);
        dst[index + 1] = @intCast((clamped_value >> 8) & 0xFF);
    }
}

fn mixDownS8(
    dst: []u8,
    mix_buffer: []const f32,
    num_channels: usize,
    channel_index: usize,
    vol: f32,
) void {
    std.debug.assert(dst.len == mix_buffer.len * num_channels);

    const mul = vol * 127.0;

    var i: usize = 0;
    while (i < mix_buffer.len) : (i += 1) {
        const value = mix_buffer[i] * mul;

        const clamped_value =
            if (value <= -127.0)
            @as(i8, -127)
        else if (value >= 126.0)
            @as(i8, 126)
        else if (value != value) // NaN
            @as(i8, 0)
        else
            @as(i8, @intFromFloat(value));

        dst[i * num_channels + channel_index] = @bitCast(clamped_value);
    }
}
