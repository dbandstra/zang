const std = @import("std");

// this delay module is not able to handle changes in sample rate, or changes
// in the delay time, so it's not quite ready for prime time. i need to figure
// out how to deal with reallocating(?) the delay buffer when the sample rate
// or delay time changes.
pub fn Delay(comptime delay_samples: usize) type {
    return struct {
        delay_buffer: [delay_samples]f32,
        delay_buffer_index: usize, // this wraps around. always < delay_samples

        pub fn init() @This() {
            return @This(){
                .delay_buffer = [1]f32{0.0} ** delay_samples,
                .delay_buffer_index = 0,
            };
        }

        pub fn reset(self: *@This()) void {
            std.mem.set(f32, &self.delay_buffer, 0.0);
            self.delay_buffer_index = 0.0;
        }

        // caller calls this first. returns the number of samples actually
        // written, which might be less than out.len. caller is responsible for
        // calling this function repeatedly with the remaining parts of `out`,
        // until the function returns out.len.
        pub fn readDelayBuffer(self: *@This(), out: []f32) usize {
            const actual_out = if (out.len > delay_samples)
                out[0..delay_samples]
            else
                out;

            const index = self.delay_buffer_index;
            const len = std.math.min(delay_samples - index, actual_out.len);
            const delay_slice = self.delay_buffer[index .. index + len];

            // paint from delay buffer to output
            var i: usize = 0;
            while (i < len) : (i += 1) {
                actual_out[i] += delay_slice[i];
            }

            if (len < actual_out.len) {
                // wrap around to the start of the delay buffer, and
                // perform the same operations as above with the remaining
                // part of the input/output
                const b_len = actual_out.len - len;

                i = 0;
                while (i < b_len) : (i += 1) {
                    actual_out[len + i] += self.delay_buffer[i];
                }
            }

            return actual_out.len;
        }

        // each time readDelayBuffer is called, this must be called after, with
        // a slice corresponding to the number of samples returned by
        // readDelayBuffer.
        pub fn writeDelayBuffer(self: *@This(), input: []const f32) void {
            std.debug.assert(input.len <= delay_samples);

            // copy input to delay buffer and increment delay_buffer_index.
            // we'll have to do this in up to two steps (in case we are
            // wrapping around the delay buffer)
            const index = self.delay_buffer_index;
            const len = std.math.min(delay_samples - index, input.len);
            const delay_slice = self.delay_buffer[index .. index + len];

            // paint from input into delay buffer
            std.mem.copy(f32, delay_slice, input[0..len]);

            if (len < input.len) {
                // wrap around to the start of the delay buffer, and
                // perform the same operations as above with the remaining
                // part of the input/output
                const b_len = input.len - len;
                std.mem.copy(f32, self.delay_buffer[0..b_len], input[len..]);
                self.delay_buffer_index = b_len;
            } else {
                // wrapping not needed
                self.delay_buffer_index += len;
                if (self.delay_buffer_index == delay_samples) {
                    self.delay_buffer_index = 0;
                }
            }
        }
    };
}
