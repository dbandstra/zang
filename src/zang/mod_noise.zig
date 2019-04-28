const std = @import("std");

pub const Noise = struct {
    pub const NumOutputs = 1;
    pub const NumInputs = 0;
    pub const NumTemps = 0;
    pub const Params = struct {};

    r: std.rand.Xoroshiro128,

    pub fn init(seed: u64) Noise {
        return Noise{
            .r = std.rand.DefaultPrng.init(seed),
        };
    }

    pub fn reset(self: *Noise) void {}

    pub fn paintSpan(self: *Noise, sample_rate: f32, outputs: [NumOutputs][]f32, inputs: [NumInputs][]f32, temps: [NumTemps][]f32, params: Params) void {
        const buf = outputs[0];
        var r = self.r;
        var i: usize = 0;

        while (i < buf.len) : (i += 1) {
            buf[i] = r.random.float(f32) * 2.0 - 1.0;
        }

        self.r = r;
    }
};