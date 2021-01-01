const std = @import("std");
const Impulse = @import("notes.zig").Impulse;
const Notes = @import("notes.zig").Notes;
const Span = @import("basics.zig").Span;

pub const ConstantOrBuffer = union(enum) {
    constant: f32,
    buffer: []const f32,
};

pub fn constant(x: f32) ConstantOrBuffer {
    return .{ .constant = x };
}

pub fn buffer(buf: []const f32) ConstantOrBuffer {
    return .{ .buffer = buf };
}

pub fn Trigger(comptime ParamsType: type) type {
    const NoteSpanNote = struct {
        id: usize,
        params: ParamsType,
    };

    const NoteSpan = struct {
        start: usize,
        end: usize,
        note: ?NoteSpanNote,
    };

    return struct {
        // once set, this is never set back to null, because note-off should
        // still be rendered (for envelope release)
        note: ?NoteSpanNote,

        pub const Counter = struct {
            iap: Notes(ParamsType).ImpulsesAndParamses,
            impulse_index: usize,
            start: usize,
            end: usize,
        };

        pub const NewPaintReturnValue = struct {
            span: Span,
            params: ParamsType,
            note_id_changed: bool,
        };

        pub fn init() @This() {
            return @This(){
                .note = null,
            };
        }

        pub fn reset(self: *@This()) void {
            self.note = null;
        }

        pub fn counter(
            self: *@This(),
            span: Span,
            iap: Notes(ParamsType).ImpulsesAndParamses,
        ) Counter {
            return Counter{
                .iap = iap,
                .impulse_index = 0,
                .start = span.start,
                .end = span.end,
            };
        }

        pub fn next(self: *@This(), ctr: *Counter) ?NewPaintReturnValue {
            while (ctr.start < ctr.end) {
                // first, try to continue a previously started note (this will
                // peek ahead in order to stop as soon as the first next new
                // note comes). then, take impulses from the ctr
                // (getNextNoteSpan).
                const note_span = carryOver(ctr, self.note) orelse getNextNoteSpan(ctr);

                ctr.start = note_span.end;

                if (note_span.note) |note| {
                    defer self.note = note;

                    return NewPaintReturnValue{
                        .span = Span.init(note_span.start, note_span.end),
                        .params = note.params,
                        .note_id_changed = if (self.note) |self_note|
                            note.id != self_note.id
                        else
                            true,
                    };
                }
            }

            return null;
        }

        fn carryOver(ctr: *const Counter, current_note: ?NoteSpanNote) ?NoteSpan {
            // check for currently playing note
            if (current_note) |note| {
                if (ctr.impulse_index < ctr.iap.impulses.len) {
                    const next_impulse_frame =
                        ctr.iap.impulses[ctr.impulse_index].frame;

                    if (next_impulse_frame > ctr.start) {
                        // next impulse starts later, so play the current note
                        // for now
                        return NoteSpan{
                            .start = ctr.start,
                            .end = std.math.min(ctr.end, next_impulse_frame),
                            .note = note,
                        };
                    } else {
                        // next impulse starts now
                        return null;
                    }
                } else {
                    // no new impulses - play current note for the whole buffer
                    return NoteSpan{
                        .start = ctr.start,
                        .end = ctr.end,
                        .note = note,
                    };
                }
            } else {
                return null;
            }
        }

        fn getNextNoteSpan(ctr: *Counter) NoteSpan {
            const impulses = ctr.iap.impulses[ctr.impulse_index..];
            const paramses = ctr.iap.paramses[ctr.impulse_index..];

            for (impulses) |impulse, i| {
                if (impulse.frame >= ctr.end) {
                    // this impulse (and all after it, since they're in
                    // chronological order) starts after the end of the buffer.
                    // this should never happen (the impulses coming in should
                    // have been clipped already)
                    break;
                }

                if (impulse.frame > ctr.start) {
                    // gap before the note begins
                    return NoteSpan{
                        .start = ctr.start,
                        .end = impulse.frame,
                        .note = null,
                    };
                }

                std.debug.assert(impulse.frame == ctr.start);

                ctr.impulse_index += 1;

                // this span ends at the start of the next impulse (if one
                // exists), or the end of the buffer, whichever comes first
                const note_end_clipped =
                    if (i + 1 < impulses.len)
                    std.math.min(ctr.end, impulses[i + 1].frame)
                else
                    ctr.end;

                if (note_end_clipped <= ctr.start) {
                    // either the impulse is entirely in the past (which
                    // should be impossible), or the next one starts at the
                    // same time
                    continue;
                }

                return NoteSpan{
                    .start = ctr.start,
                    .end = note_end_clipped,
                    .note = NoteSpanNote{
                        .id = impulse.note_id,
                        .params = paramses[i],
                    },
                };
            }

            // no more impulses
            return NoteSpan{
                .start = ctr.start,
                .end = ctr.end,
                .note = null,
            };
        }
    };
}
