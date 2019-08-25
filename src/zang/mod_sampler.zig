const std = @import("std");
const WavContents = @import("read_wav.zig").WavContents;
const Span = @import("basics.zig").Span;

// FIXME - no effort at all has been made to optimize the sampler module
// FIXME - hardcoded to support only 16-bit wav files
// FIXME - use a better resampling filter
// TODO - more complex looping schemes
// TODO - allow sample_rate to be controlled

fn getSample(data: []const u8, num_channels: usize, index1: i32, channel: usize, loop: bool) f32 {
    const num_samples = @intCast(i32, data.len / 2 / num_channels);
    const index = if (loop) @mod(index1, num_samples) else index1;

    if (index >= 0 and index < num_samples) {
        const i = @intCast(usize, index) * num_channels + channel;

        const b0 = data[i * 2 + 0];
        const b1 = data[i * 2 + 1];

        const uval = u16(b0) | (u16(b1) << 8);
        const sval = @bitCast(i16, uval);

        return @intToFloat(f32, sval) / 32768.0;
    } else {
        return 0.0;
    }
}

pub const Sample = struct {
    num_channels: usize,
    sample_rate: usize,
    bytes_per_sample: usize, // must be 2
    data: []const u8,
};

pub const Sampler = struct {
    pub const num_outputs = 1;
    pub const num_temps = 0;
    pub const Params = struct {
        sample_rate: f32,
        sample: Sample,
        channel: usize,
        loop: bool,
    };

    t: f32,

    pub fn init() Sampler {
        return Sampler {
            .t = 0.0,
        };
    }

    pub fn paint(self: *Sampler, span: Span, outputs: [num_outputs][]f32, temps: [num_temps][]f32, note_id_changed: bool, params: Params) void {
        if (params.sample.bytes_per_sample != 2) {
            std.debug.panic("TODO - Sampler: support non-16-bit samples\n");
        }
        if (params.channel >= params.sample.num_channels) {
            return;
        }

        if (note_id_changed) {
            self.t = 0.0;
        }

        const out = outputs[0][span.start..span.end];

        const ratio = @intToFloat(f32, params.sample.sample_rate) / params.sample_rate;

        if (ratio < 0.0 and !params.loop) {
            // i don't think it makes sense to play backwards without looping
            return;
        }

        // FIXME - pulled these epsilon values out of my ass
        if (ratio > 0.9999 and ratio < 1.0001) {
            // no resampling needed
            const t = @floatToInt(i32, std.math.round(self.t));

            var i: u31 = 0; while (i < out.len) : (i += 1) {
                out[i] += getSample(params.sample.data, params.sample.num_channels, t + i32(i), params.channel, params.loop);
            }

            self.t += @intToFloat(f32, out.len);
        } else {
            // resample
            var i: u31 = 0; while (i < out.len) : (i += 1) {
                const t0 = @floatToInt(i32, std.math.floor(self.t));
                const t1 = t0 + 1;
                const tfrac = @intToFloat(f32, t1) - self.t;

                const s0 = getSample(params.sample.data, params.sample.num_channels, t0, params.channel, params.loop);
                const s1 = getSample(params.sample.data, params.sample.num_channels, t1, params.channel, params.loop);

                const s = s0 * (1.0 - tfrac) + s1 * tfrac;

                out[i] += s;

                self.t += ratio;
            }
        }

        if (self.t >= @intToFloat(f32, params.sample.data.len) and params.loop) {
            self.t -= @intToFloat(f32, params.sample.data.len);
        }
    }
};
