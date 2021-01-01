const std = @import("std");
const zang = @import("zang");
const wav = @import("zig-wav");

const example = @import("example_song.zig");

const TOTAL_TIME = 19 * example.AUDIO_SAMPLE_RATE;

const bytes_per_sample = switch (example.AUDIO_FORMAT) {
    .signed8 => 1,
    .signed16_lsb => 2,
};

var g_outputs: [example.MainModule.num_outputs][example.AUDIO_BUFFER_SIZE]f32 = undefined;
var g_temps: [example.MainModule.num_temps][example.AUDIO_BUFFER_SIZE]f32 = undefined;

var g_big_buffer: [TOTAL_TIME * bytes_per_sample * example.MainModule.num_outputs]u8 = undefined;

pub fn main() !void {
    var main_module = example.MainModule.init();

    // TODO stream directly to wav file instead of to the "big buffer" (this
    // might require expanding the zig-wav API - it will need to be able to
    // seek back and write the length after streaming is done).
    var start: usize = 0;
    while (start < TOTAL_TIME) {
        const len = std.math.min(example.AUDIO_BUFFER_SIZE, TOTAL_TIME - start);

        const span = zang.Span.init(0, len);

        var outputs: [example.MainModule.num_outputs][]f32 = undefined;
        for (outputs) |*output, i| {
            output.* = &g_outputs[i];
            zang.zero(span, output.*);
        }

        var temps: [example.MainModule.num_temps][]f32 = undefined;
        for (temps) |*temp, i| {
            temp.* = &g_temps[i];
        }

        main_module.paint(span, outputs, temps);

        for (outputs) |output, i| {
            const m = bytes_per_sample * example.MainModule.num_outputs;
            const out_slice = g_big_buffer[start * m .. (start + len) * m];
            zang.mixDown(
                out_slice,
                output[span.start..span.end],
                example.AUDIO_FORMAT,
                example.MainModule.num_outputs,
                i,
                0.25,
            );
            if (example.AUDIO_FORMAT == .signed8) {
                // wav files use unsigned 8-bit, so convert
                for (out_slice) |*byte| {
                    const signed_byte = @bitCast(i8, byte.*);
                    byte.* = @intCast(u8, i16(signed_byte) + 128);
                }
            }
        }

        start += len;
    }

    const file = try std.fs.cwd().createFile("out.wav", .{});
    defer file.close();
    var stream = file.outStream();
    try wav.Saver(@TypeOf(stream)).save(&stream, .{
        .num_channels = example.MainModule.num_outputs,
        .sample_rate = example.AUDIO_SAMPLE_RATE,
        .format = switch (example.AUDIO_FORMAT) {
            .signed8 => .unsigned8,
            .signed16_lsb => .signed16_lsb,
        },
        .data = &g_big_buffer,
    });
}
