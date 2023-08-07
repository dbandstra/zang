const std = @import("std");
const c = @import("common").c;

// records and plays back keypresses. press the button once to start recording,
// press again to stop recording and play back in a loop what was recorded,
// press a third time to turn it off.

// one problem is that if you're playing along to the playback, your notes will
// also get cut off every time it loops. but i don't care to fix it. this
// feature was mostly intended so that you can leave something playing while
// you tweak instrument parameters. it will probably be eventually be replaced
// by a proper music tracking system.

// also, i think it has problems if you press a key that is already down
// according to the playback. it's possible to lose the note up event and the
// note will keep playing after you let go. but again i think it's good enough.

pub const Recorder = struct {
    pub const State = union(enum) {
        idle,
        recording: struct {
            start_time: f32,
        },
        playing: struct {
            start_time: f32,
            duration: f32,
            note_index: usize,
            looping: bool,
        },
    };

    pub const Note = struct {
        key: i32,
        down: bool,
        time: f32,
    };

    pub const GetNoteResult = struct {
        key: i32,
        down: bool,
    };

    pub const max_notes = 5000;
    pub const max_keys_held = 50;

    state: State,
    notes: [max_notes]Note,
    num_notes: usize,
    keys_held: [max_keys_held]i32,
    num_keys_held: usize,
    drain_keys_held: bool,

    fn getTime() f32 {
        return @as(f32, @floatFromInt(c.SDL_GetTicks())) / 1000.0;
    }

    pub fn init() Recorder {
        return Recorder{
            .state = .idle,
            .notes = undefined,
            .num_notes = 0,
            .keys_held = undefined,
            .num_keys_held = 0,
            .drain_keys_held = false,
        };
    }

    pub fn cycleMode(self: *Recorder) void {
        self.drain_keys_held = true;
    }

    pub fn recordEvent(self: *Recorder, key: i32, down: bool) void {
        const r = switch (self.state) {
            .recording => |r| r,
            else => return,
        };
        if (self.num_notes == max_notes) return;
        self.notes[self.num_notes] = .{
            .key = key,
            .down = down,
            .time = getTime() - r.start_time,
        };
        self.num_notes += 1;
        return;
    }

    pub fn trackEvent(self: *Recorder, key: i32, down: bool) void {
        if (down) {
            for (self.keys_held[0..self.num_keys_held]) |key_held| {
                if (key_held == key) break;
            } else if (self.num_keys_held < max_keys_held) {
                self.keys_held[self.num_keys_held] = key;
                self.num_keys_held += 1;
            }
        } else {
            if (std.mem.indexOfScalar(i32, self.keys_held[0..self.num_keys_held], key)) |index| {
                var i = index;
                while (i < self.num_keys_held - 1) : (i += 1) {
                    self.keys_held[i] = self.keys_held[i + 1];
                }
                self.num_keys_held -= 1;
            }
        }
    }

    pub fn getNote(self: *Recorder) ?GetNoteResult {
        if (self.drain_keys_held) {
            if (self.num_keys_held > 0) {
                self.num_keys_held -= 1;
                return GetNoteResult{
                    .key = self.keys_held[self.num_keys_held],
                    .down = false,
                };
            }

            self.drain_keys_held = false;
            switch (self.state) {
                .idle => {
                    self.state = .{
                        .recording = .{
                            .start_time = getTime(),
                        },
                    };
                    self.num_notes = 0;
                },
                .recording => |r| {
                    self.state = .{
                        .playing = .{
                            .start_time = getTime(),
                            .duration = getTime() - r.start_time,
                            .note_index = 0,
                            .looping = false,
                        },
                    };
                },
                .playing => |*p| {
                    if (p.looping) {
                        p.looping = false;
                    } else {
                        self.state = .idle;
                    }
                },
            }
        }

        const p = switch (self.state) {
            .playing => |*p| p,
            else => return null,
        };

        const time = getTime() - p.start_time;
        if (time >= p.duration) {
            p.note_index = 0;
            p.start_time = getTime();
            p.looping = true;
            self.drain_keys_held = true;
        }
        if (p.note_index < self.num_notes) {
            const note = self.notes[p.note_index];
            if (note.time <= time) {
                p.note_index += 1;
                return GetNoteResult{
                    .key = note.key,
                    .down = note.down,
                };
            }
        }
        return null;
    }
};
