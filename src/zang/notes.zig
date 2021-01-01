const std = @import("std");

// this can be used when pushing to an ImpulseQueue. it's all you need if you
// don't care about matching note-on and note-off events (which is only
// important for polyphony)
pub const IdGenerator = struct {
    next_id: usize,

    pub fn init() IdGenerator {
        return IdGenerator{
            .next_id = 1,
        };
    }

    pub fn nextId(self: *IdGenerator) usize {
        defer self.next_id += 1;
        return self.next_id;
    }
};

pub const Impulse = struct {
    frame: usize, // frames (e.g. 44100 for one second in)
    note_id: usize,
    event_id: usize,
};

pub fn Notes(comptime NoteParamsType: type) type {
    return struct {
        pub const ImpulsesAndParamses = struct {
            // these two slices will have the same length
            impulses: []const Impulse,
            paramses: []const NoteParamsType,
        };

        pub const ImpulseQueue = struct {
            impulses_array: [32]Impulse,
            paramses_array: [32]NoteParamsType,
            length: usize,
            next_event_id: usize,

            pub fn init() ImpulseQueue {
                return ImpulseQueue{
                    .impulses_array = undefined,
                    .paramses_array = undefined,
                    .length = 0,
                    .next_event_id = 1,
                };
            }

            // return impulses and advance state.
            // make sure to use the returned impulse list before pushing more
            // stuff
            // FIXME shouldn't this take in a span?
            // although it's probably fine now because we're never using an
            // impulse queue within something...
            pub fn consume(self: *ImpulseQueue) ImpulsesAndParamses {
                defer self.length = 0;

                return ImpulsesAndParamses{
                    .impulses = self.impulses_array[0..self.length],
                    .paramses = self.paramses_array[0..self.length],
                };
            }

            pub fn push(
                self: *ImpulseQueue,
                impulse_frame: usize,
                note_id: usize,
                params: NoteParamsType,
            ) void {
                if (self.length >= self.impulses_array.len) {
                    // std.debug.warn("ImpulseQueue: no more slots\n"); // FIXME
                    return;
                }
                if (self.length > 0 and
                    impulse_frame < self.impulses_array[self.length - 1].frame)
                {
                    // you must push impulses in order. this could even be a panic
                    // std.debug.warn("ImpulseQueue: notes pushed out of order\n");
                    return;
                }
                self.impulses_array[self.length] = Impulse{
                    .frame = impulse_frame,
                    .note_id = note_id,
                    .event_id = self.next_event_id,
                };
                self.paramses_array[self.length] = params;
                self.length += 1;
                self.next_event_id += 1;
            }
        };

        pub const SongEvent = struct {
            params: NoteParamsType,
            t: f32,
            note_id: usize,
        };

        // follow a canned melody, creating impulses from it, one mix buffer
        // at a time
        pub const NoteTracker = struct {
            song: []const SongEvent,
            next_song_event: usize,
            t: f32,
            impulses_array: [32]Impulse, // internal storage
            paramses_array: [32]NoteParamsType,

            pub fn init(song: []const SongEvent) NoteTracker {
                return .{
                    .song = song,
                    .next_song_event = 0,
                    .t = 0.0,
                    .impulses_array = undefined,
                    .paramses_array = undefined,
                };
            }

            pub fn reset(self: *NoteTracker) void {
                self.next_song_event = 0;
                self.t = 0.0;
            }

            // return impulses for notes that fall within the upcoming buffer
            // frame.
            pub fn consume(
                self: *NoteTracker,
                sample_rate: f32,
                out_len: usize,
            ) ImpulsesAndParamses {
                var count: usize = 0;

                const buf_time = @intToFloat(f32, out_len) / sample_rate;
                var start_t = self.t;
                const end_t = self.t + buf_time;

                for (self.song[self.next_song_event..]) |song_event| {
                    const note_t = song_event.t;
                    // the notes must have been provided in chronological order
                    std.debug.assert(note_t >= start_t);
                    if (note_t < end_t) {
                        const f = (note_t - self.t) / buf_time; // 0 to 1
                        const rel_frame_index = std.math.min(
                            @floatToInt(usize, f * @intToFloat(f32, out_len)),
                            out_len - 1,
                        );
                        // TODO - do something graceful-ish when count >=
                        // self.impulse_array.len
                        self.next_song_event += 1;
                        self.impulses_array[count] = Impulse{
                            .frame = rel_frame_index,
                            .note_id = song_event.note_id,
                            .event_id = self.next_song_event,
                        };
                        self.paramses_array[count] = song_event.params;
                        count += 1;
                        start_t = note_t;
                    } else {
                        break;
                    }
                }

                self.t = end_t;

                return ImpulsesAndParamses{
                    .impulses = self.impulses_array[0..count],
                    .paramses = self.paramses_array[0..count],
                };
            }
        };

        pub fn PolyphonyDispatcher(comptime polyphony: usize) type {
            const SlotState = struct {
                // each note-on/off combo has the same note_id. this is used
                // to match them up
                note_id: usize,
                // note-on and off have unique event_ids. these monotonically
                // increase and are used to determine the "stalest" slot (to
                // be reused)
                event_id: usize,
                // polyphony only works when the ParamsType includes note_on.
                // we need this to be able to determine when to reuse slots
                note_on: bool,
            };

            return struct {
                slots: [polyphony]?SlotState,
                // TODO - i should be able to use a single array for each of
                // these because only 32 impulses can come in, only 32
                // impulses could come out... or can i even reuse the storage
                // of the NoteTracker?
                impulses_array: [polyphony][32]Impulse, // internal storage
                paramses_array: [polyphony][32]NoteParamsType,

                pub fn init() @This() {
                    return @This(){
                        .slots = [1]?SlotState{null} ** polyphony,
                        .impulses_array = undefined,
                        .paramses_array = undefined,
                    };
                }

                pub fn reset(self: *@This()) void {
                    for (self.slots) |*maybe_slot| {
                        maybe_slot.* = null;
                    }
                }

                fn chooseSlot(
                    self: *const @This(),
                    note_id: usize,
                    event_id: usize,
                    note_on: bool,
                ) ?usize {
                    if (!note_on) {
                        // this is a note-off event. try to find the slot where
                        // the note lives. if we don't find it (meaning it got
                        // overridden at some point), return null
                        return for (self.slots) |maybe_slot, slot_index| {
                            if (maybe_slot) |slot| {
                                if (slot.note_id == note_id and slot.note_on) {
                                    break slot_index;
                                }
                            }
                        } else null;
                    }
                    // otherwise, this is a note-on event. find the slot in
                    // note-off state with the oldest event_id. this will reuse
                    // will reuse the slot that had its note-off the longest
                    // time ago.
                    {
                        var maybe_best: ?usize = null;
                        for (self.slots) |maybe_slot, slot_index| {
                            if (maybe_slot) |slot| {
                                if (!slot.note_on) {
                                    if (maybe_best) |best| {
                                        if (slot.event_id <
                                            self.slots[best].?.event_id)
                                        {
                                            maybe_best = slot_index;
                                        }
                                    } else { // maybe_best == null
                                        maybe_best = slot_index;
                                    }
                                }
                            } else { // maybe_slot == null
                                // if there's still an empty slot, jump on
                                // that right now
                                return slot_index;
                            }
                        }
                        if (maybe_best) |best| {
                            return best;
                        }
                    }
                    // otherwise, we have no choice but to take over a track
                    // that's still in note-on state.
                    var best: usize = 0;
                    var slot_index: usize = 1;
                    while (slot_index < polyphony) : (slot_index += 1) {
                        if (self.slots[slot_index].?.event_id <
                            self.slots[best].?.event_id)
                        {
                            best = slot_index;
                        }
                    }
                    return best;
                }

                // FIXME can this be changed to a generator pattern so we don't
                // need the static arrays?
                pub fn dispatch(
                    self: *@This(),
                    iap: ImpulsesAndParamses,
                ) [polyphony]ImpulsesAndParamses {
                    var counts = [1]usize{0} ** polyphony;

                    var i: usize = 0;
                    while (i < iap.paramses.len) : (i += 1) {
                        const impulse = iap.impulses[i];
                        const params = iap.paramses[i];

                        if (self.chooseSlot(
                            impulse.note_id,
                            impulse.event_id,
                            params.note_on,
                        )) |slot_index| {
                            self.slots[slot_index] = SlotState{
                                .note_id = impulse.note_id,
                                .event_id = impulse.event_id,
                                .note_on = params.note_on,
                            };

                            self.impulses_array[slot_index][counts[slot_index]] = impulse;
                            self.paramses_array[slot_index][counts[slot_index]] = params;
                            counts[slot_index] += 1;
                        }
                    }

                    var result: [polyphony]ImpulsesAndParamses = undefined;
                    i = 0;
                    while (i < polyphony) : (i += 1) {
                        result[i] = ImpulsesAndParamses{
                            .impulses = self.impulses_array[i][0..counts[i]],
                            .paramses = self.paramses_array[i][0..counts[i]],
                        };
                    }
                    return result;
                }
            };
        }
    };
}
