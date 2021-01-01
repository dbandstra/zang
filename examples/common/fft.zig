const std = @import("std");

fn fftBitReverse(N: usize, re: []f32, im: []f32) void {
    const i_2 = N >> 1;
    var j: usize = 0;

    var h: usize = 0;
    while (h < N - 2) : (h += 1) {
        if (h < j) {
            const tmp0 = re[h];
            re[h] = re[j];
            re[j] = tmp0;
            const tmp1 = im[h];
            im[h] = im[j];
            im[j] = tmp1;
        }
        var k = i_2;
        while (k <= j) : (k >>= 1) {
            j -= k;
        }
        j += k;
    }
}

pub fn fft(N: usize, re: []f32, im: []f32) void {
    var l2: usize = 1;
    var c: f32 = -1.0;
    var s: f32 = 0.0;

    fftBitReverse(N, re, im);

    var k: usize = 1;
    while (k < N) : (k <<= 1) {
        const l1 = l2;
        l2 <<= 1;
        var u_1: f32 = 1.0;
        var u_2: f32 = 0.0;
        var j: usize = 0;
        while (j < l1) : (j += 1) {
            var t1: f32 = undefined;
            var t2: f32 = undefined;
            var h = j;
            while (h < N) : (h += l2) {
                const i_1 = h + l1;
                t2 = (re[i_1] - im[i_1]) * u_2;
                t1 = t2 + re[i_1] * (u_1 - u_2);
                t2 = t2 + im[i_1] * (u_1 + u_2);
                re[i_1] = re[h] - t1;
                im[i_1] = im[h] - t2;
                re[h] += t1;
                im[h] += t2;
            }
            t1 = u_1 * c - u_2 * s;
            u_2 = u_1 * s + u_2 * c;
            u_1 = t1;
        }
        s = -std.math.sqrt((1 - c) * 0.5);
        c = std.math.sqrt((1 + c) * 0.5);
    }
}
