// pink noise implementation from here (paul kellett, public domain):
// http://www.firstpr.com.au/dsp/pink-noise/

const std = @import("std");
const Span = @import("basics.zig").Span;

// use u32 instead of u64 because wasm doesn't support u64 in @atomicRmw.
// TODO would the `threadlocal` zig keyword make this easier?
var next_seed: u32 = 0;

pub const NoiseColor = enum {
    white,
    pink,
};

pub const Noise = struct {
    pub const num_outputs = 1;
    pub const num_temps = 0;
    pub const Params = struct {
        color: NoiseColor,
    };

    r: std.rand.Xoroshiro128,
    b: [7]f32,

    pub fn init() Noise {
        const seed: u64 = @atomicRmw(u32, &next_seed, .Add, 1, .SeqCst);

        return .{
            .r = std.rand.Xoroshiro128.init(seed),
            .b = [1]f32{0.0} ** 7,
        };
    }

    pub fn paint(
        self: *Noise,
        span: Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        const out = outputs[0];
        var r = self.r;
        switch (params.color) {
            .white => {
                var i = span.start;
                while (i < span.end) : (i += 1) {
                    out[i] += r.random.float(f32) * 2.0 - 1.0;
                }
            },
            .pink => {
                var b = self.b;
                var i = span.start;
                while (i < span.end) : (i += 1) {
                    const white = r.random.float(f32) * 2.0 - 1.0;
                    b[0] = 0.99886 * b[0] + white * 0.0555179;
                    b[1] = 0.99332 * b[1] + white * 0.0750759;
                    b[2] = 0.96900 * b[2] + white * 0.1538520;
                    b[3] = 0.86650 * b[3] + white * 0.3104856;
                    b[4] = 0.55000 * b[4] + white * 0.5329522;
                    b[5] = -0.7616 * b[5] - white * 0.0168980;
                    out[i] += b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + white * 0.5362;
                    b[6] = white * 0.115926;
                }
                b = self.b;
            },
        }
        self.r = r;
    }
};
