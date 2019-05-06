const std = @import("std");
const addInto = @import("basics.zig").addInto;
const copy = @import("basics.zig").copy;

// this delay module is not able to handle changes in sample rate, or changes
// in the delay time, so it's not quite ready for prime time. i need to figure
// out how to deal with reallocating(?) the delay buffer when the sample rate
// or delay time changes.
pub fn Delay(comptime DELAY_SAMPLES: usize) type {
    return struct {
        delay_buffer: [DELAY_SAMPLES]f32,
        delay_buffer_index: usize, // this will wrap around. always < DELAY_SAMPLES

        pub fn init() @This() {
            return @This() {
                .delay_buffer = [1]f32{0.0} ** DELAY_SAMPLES,
                .delay_buffer_index = 0,
            };
        }

        // caller calls this first. returns the number of samples actually
        // written, which might be less than out.len. caller is responsible for
        // calling this function repeatedly with the remaining parts of `out`,
        // until the function returns out.len.
        pub fn readDelayBuffer(self: *@This(), out: []f32) usize {
            const actual_out =
                if (out.len > DELAY_SAMPLES)
                    out[0..DELAY_SAMPLES]
                else
                    out;

            const len = min(usize, DELAY_SAMPLES - self.delay_buffer_index, actual_out.len);
            const delay_slice = self.delay_buffer[self.delay_buffer_index .. self.delay_buffer_index + len];

            // paint from delay buffer to output
            addInto(actual_out[0..len], delay_slice);

            if (len < actual_out.len) {
                // wrap around to the start of the delay buffer, and
                // perform the same operations as above with the remaining
                // part of the input/output
                const b_len = actual_out.len - len;
                addInto(actual_out[len..], self.delay_buffer[0..b_len]);
            }

            return actual_out.len;
        }

        // each time readDelayBuffer is called, this must be called after, with
        // a slice corresponding to the number of samples returned by
        // readDelayBuffer.
        pub fn writeDelayBuffer(self: *@This(), input: []const f32) void {
            std.debug.assert(input.len <= DELAY_SAMPLES);

            // copy input to delay buffer and increment delay_buffer_index.
            // we'll have to do this in up to two steps (in case we are
            // wrapping around the delay buffer)
            const len = min(usize, DELAY_SAMPLES - self.delay_buffer_index, input.len);
            const delay_slice = self.delay_buffer[self.delay_buffer_index .. self.delay_buffer_index + len];

            // paint from input into delay buffer
            copy(delay_slice, input[0..len]);

            if (len < input.len) {
                // wrap around to the start of the delay buffer, and
                // perform the same operations as above with the remaining
                // part of the input/output
                const b_len = input.len - len;
                copy(self.delay_buffer[0..b_len], input[len..]);
                self.delay_buffer_index = b_len;
            } else {
                // wrapping not needed
                self.delay_buffer_index += len;
                if (self.delay_buffer_index == DELAY_SAMPLES) {
                    self.delay_buffer_index = 0;
                }
            }
        }
    };
}

inline fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}