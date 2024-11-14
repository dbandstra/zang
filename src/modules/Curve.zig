const std = @import("std");
const zang = @import("zang");

pub const InterpolationFunction = enum {
    linear,
    smoothstep,
};

// curves are like notes except the value will be interpolated in between them.
// they can't be created in real-time
const CurveSpanNode = struct {
    frame: i32, // frames (e.g. 44100 for one second in)
    value: f32,
};

const CurveSpanValues = struct {
    start_node: CurveSpanNode,
    end_node: CurveSpanNode,
};

const CurveSpan = struct {
    start: usize,
    end: usize,
    values: ?CurveSpanValues, // if null, this is a silent gap between curves
};

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    sample_rate: f32,
    function: InterpolationFunction,
    curve: []const zang.CurveNode,
};

// progress through the curve, in seconds
t: f32,
// some state to make it faster to continue painting. note: this relies on
// the curve param not being mutated by the caller
current_song_note: usize,
current_song_note_offset: i32,
next_song_note: usize,
// this is just some memory set aside for temporary use during a paint
// call. it could just as easily be a stack local
curve_nodes: [32]CurveSpanNode,

pub fn init() @This() {
    return .{
        .current_song_note = 0,
        .current_song_note_offset = 0,
        .next_song_note = 0,
        .t = 0.0,
        .curve_nodes = undefined,
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

    if (note_id_changed) {
        self.current_song_note = 0;
        self.current_song_note_offset = 0;
        self.next_song_note = 0;
        self.t = 0.0;
    }

    const out = outputs[0][span.start..span.end];
    const curve_nodes = self.getCurveSpanNodes(params.sample_rate, out.len, params.curve);

    var start: usize = 0;

    while (start < out.len) {
        const curve_span = getNextCurveSpan(curve_nodes, start, out.len);

        const paint_start: i32 = @intCast(curve_span.start);
        // const paint_end: i32 = @intCast(curve_span.end);

        if (curve_span.values) |values| {
            // the full range between nodes
            const fstart = values.start_node.frame;
            const fend = values.end_node.frame;

            // std.debug.assert(fstart < fend);
            // std.debug.assert(fstart <= paint_start);
            // std.debug.assert(curve_span.start < paint_end);
            // std.debug.assert(curve_span.end <= fend);

            // 'x' values are 0-1
            const start_x = @as(f32, @floatFromInt(paint_start - fstart)) / @as(f32, @floatFromInt(fend - fstart));

            const start_value = values.start_node.value;
            const value_delta = values.end_node.value - values.start_node.value;

            const x_step = 1.0 / @as(f32, @floatFromInt(fend - fstart));

            var i: usize = curve_span.start;

            switch (params.function) {
                .linear => {
                    var y = start_value + start_x * value_delta;
                    const y_step = x_step * value_delta;

                    while (i < curve_span.end) : (i += 1) {
                        out[i] += y;
                        y += y_step;
                    }
                },
                .smoothstep => {
                    var x = start_x;

                    while (i < curve_span.end) : (i += 1) {
                        const v = x * x * (3.0 - 2.0 * x) * value_delta;
                        out[i] += start_value + v;
                        x += x_step;
                    }
                },
            }
        }

        start = curve_span.end;
    }
}

fn getCurveSpanNodes(
    self: *@This(),
    sample_rate: f32,
    out_len: usize,
    curve_nodes: []const zang.CurveNode,
) []CurveSpanNode {
    var count: usize = 0;

    const buf_time = @as(f32, @floatFromInt(out_len)) / sample_rate;
    const end_t = self.t + buf_time;

    // add a note that was begun in a previous frame
    if (self.current_song_note < self.next_song_note) {
        self.curve_nodes[count] = .{
            .frame = self.current_song_note_offset,
            .value = curve_nodes[self.current_song_note].value,
        };
        count += 1;
    }

    var one_past = false;
    for (curve_nodes[self.next_song_note..]) |song_note| {
        const note_t = song_note.t;
        if (note_t >= end_t) {
            // keep one note past the end
            if (!one_past) {
                one_past = true;
            } else {
                break;
            }
        }
        const f = (note_t - self.t) / buf_time; // 0 to 1
        const rel_frame_index: i32 = @intFromFloat(f * @as(f32, @floatFromInt(out_len)));
        // if there's already a note at this frame (from the previous note
        // carry-over), this should overwrite that one
        if (count > 0 and self.curve_nodes[count - 1].frame == rel_frame_index) {
            count -= 1;
        }
        self.curve_nodes[count] = .{
            .frame = rel_frame_index,
            .value = song_note.value,
        };
        count += 1;
        if (!one_past) {
            self.current_song_note = self.next_song_note;
            self.current_song_note_offset = 0;
            self.next_song_note += 1;
        }
    }

    self.t += buf_time;
    self.current_song_note_offset -= @as(i32, @intCast(out_len));

    return self.curve_nodes[0..count];
}

// note: will possibly emit an end node past the end of the buffer (necessary
// for interpolation)
fn getNextCurveSpan(curve_nodes: []const CurveSpanNode, dest_start_: usize, dest_end_: usize) CurveSpan {
    std.debug.assert(dest_start_ < dest_end_);

    const dest_start: i32 = @intCast(dest_start_);
    const dest_end: i32 = @intCast(dest_end_);

    for (curve_nodes, 0..) |curve_node, i| {
        const start_pos = curve_node.frame;

        if (start_pos >= dest_end) {
            // this curve_node (and all after it, since they're in
            // chronological order) starts after the end of the buffer
            break;
        }

        // this span ends at the start of the next curve_node (if one exists),
        // or the end of the buffer, whichever comes first
        const end_pos = if (i < curve_nodes.len - 1)
            @min(dest_end, curve_nodes[i + 1].frame)
        else
            dest_end;

        if (end_pos <= dest_start) {
            // curve_node is entirely in the past. skip it
            continue;
        }

        const note_start_clipped = if (start_pos > dest_start)
            start_pos
        else
            dest_start;

        if (note_start_clipped > dest_start) {
            // gap before the note begins
            return .{
                .start = @intCast(dest_start),
                .end = @intCast(note_start_clipped),
                .values = null,
            };
        }

        const note_end = end_pos;
        const note_end_clipped = if (note_end > dest_end)
            dest_end
        else
            note_end;

        return .{
            .start = @intCast(note_start_clipped),
            .end = @intCast(note_end_clipped),
            .values = if (i < curve_nodes.len - 1)
                CurveSpanValues{
                    .start_node = curve_node,
                    .end_node = curve_nodes[i + 1],
                }
            else
                null,
        };
    }

    std.debug.assert(dest_start < dest_end);

    return .{
        .start = @intCast(dest_start),
        .end = @intCast(dest_end),
        .values = null,
    };
}
