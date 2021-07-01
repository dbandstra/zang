const std = @import("std");
const zang = @import("zang");
const f = @import("zang-12tet");
const common = @import("common.zig");
const c = @import("common/c.zig");
const util = @import("common/util.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_song
    \\
    \\Plays a canned melody (Bach's Toccata and Fugue in D
    \\Minor).
    \\
    \\Press spacebar to restart the song.
;

const a4 = 440.0;
const NOTE_DURATION = 0.15;

// everything comes out of the text file in this format
const MyNoteParams = struct {
    freq: f32,
    note_on: bool,
};

const Pedal = struct {
    const Module = @import("modules.zig").PMOscInstrument;
    fn initModule() Module {
        return Module.init(0.4);
    }
    fn makeParams(sample_rate: f32, src: MyNoteParams) Module.Params {
        return .{
            .sample_rate = sample_rate,
            .freq = src.freq * 0.5,
            .note_on = src.note_on,
        };
    }
    const polyphony = 3;
    const num_columns = 2;
};

const RegularOrgan = struct {
    const Module = @import("modules.zig").NiceInstrument;
    fn initModule() Module {
        return Module.init(0.25);
    }
    fn makeParams(sample_rate: f32, src: MyNoteParams) Module.Params {
        return .{
            .sample_rate = sample_rate,
            .freq = src.freq,
            .note_on = src.note_on,
        };
    }
    const polyphony = 10;
    const num_columns = 8;
};

const WeirdOrgan = struct {
    const Module = @import("modules.zig").NiceInstrument;
    fn initModule() Module {
        return Module.init(0.1);
    }
    fn makeParams(sample_rate: f32, src: MyNoteParams) Module.Params {
        return .{
            .sample_rate = sample_rate,
            .freq = src.freq,
            .note_on = src.note_on,
        };
    }
    const polyphony = 4;
    const num_columns = 2;
};

// note: i would prefer for this to be an array of types (so i don't have to
// give meaningless names to the fields), but it's also being used as an
// instance type. you can't do that with an array of types. and without
// reification features i can't generate a struct procedurally. (it needs to be
// a struct because the elements/fields have different types)
const Voices = struct {
    voice0: Voice(Pedal),
    voice1: Voice(RegularOrgan),
    voice2: Voice(WeirdOrgan),
};

// this parallels the Voices struct. these values are not necessarily the same
// as the polyphony amount. they're just a parsing detail
const COLUMNS_PER_VOICE = [@typeInfo(Voices).Struct.fields.len]usize{
    Pedal.num_columns,
    RegularOrgan.num_columns,
    WeirdOrgan.num_columns,
};

const TOTAL_COLUMNS = blk: {
    var sum: usize = 0;
    for (COLUMNS_PER_VOICE) |v| sum += v;
    break :blk sum;
};

const NUM_INSTRUMENTS = COLUMNS_PER_VOICE.len;

// note we can't put params straight into Module.Params because that requires
// sample_rate which is only known at runtime
var all_notes_arr: [NUM_INSTRUMENTS][20000]zang.Notes(MyNoteParams).SongEvent = undefined;
var all_notes: [NUM_INSTRUMENTS][]zang.Notes(MyNoteParams).SongEvent = undefined;

fn makeSongNote(
    t: f32,
    id: usize,
    freq: f32,
    note_on: bool,
) zang.Notes(MyNoteParams).SongEvent {
    return .{
        .t = t,
        .note_id = id,
        .params = .{
            .freq = freq,
            .note_on = note_on,
        },
    };
}

const Parser = @import("common/songparse1.zig").Parser(TOTAL_COLUMNS);

// NOTE about polyphony: if you retrigger a note at the same frequency, it will
// be played in a separate voice (won't cut off the previous note). polyphony
// doesn't look at note frequency at all, just the on/off events.
fn doParse(parser: *Parser) !void {
    const LastNote = struct {
        freq: f32,
        id: usize,
    };
    var column_last_note = [1]?LastNote{null} ** TOTAL_COLUMNS;
    var instrument_num_notes = [1]usize{0} ** NUM_INSTRUMENTS;
    var next_id: usize = 1;

    var t: f32 = 0;
    var rate: f32 = 1.0;
    var tempo: f32 = 1.0;

    while (try parser.parseToken()) |token| {
        if (token.isWord("start")) {
            t = 0.0;
            var i: usize = 0;
            while (i < NUM_INSTRUMENTS) : (i += 1) {
                instrument_num_notes[i] = 0;
            }
            // TODO what about column_last_note?
        } else if (token.isWord("rate")) {
            rate = try parser.requireNumber();
        } else if (token.isWord("tempo")) {
            tempo = try parser.requireNumber();
        } else {
            switch (token) {
                .notes => |notes| {
                    const old_instrument_num_notes = instrument_num_notes;

                    for (notes) |note, col| {
                        const instrument_index = blk: {
                            var first_column: usize = 0;
                            for (COLUMNS_PER_VOICE) |num_columns, track_index| {
                                if (col < first_column + num_columns) {
                                    break :blk track_index;
                                }
                                first_column += num_columns;
                            }
                            unreachable;
                        };

                        var note_ptr = &all_notes_arr[instrument_index][instrument_num_notes[instrument_index]];

                        switch (note) {
                            .idle => {},
                            .freq => |freq| {
                                // note-off of previous note in this column
                                // (if present)
                                if (column_last_note[col]) |last_note| {
                                    note_ptr.* = makeSongNote(
                                        t,
                                        last_note.id,
                                        last_note.freq,
                                        false,
                                    );
                                    instrument_num_notes[instrument_index] += 1;
                                    note_ptr = &all_notes_arr[instrument_index][instrument_num_notes[instrument_index]];
                                }
                                // note-on event for the new frequency
                                note_ptr.* =
                                    makeSongNote(t, next_id, freq, true);
                                instrument_num_notes[instrument_index] += 1;
                                column_last_note[col] = LastNote{
                                    .id = next_id,
                                    .freq = freq,
                                };
                                next_id += 1;
                            },
                            .off => {
                                if (column_last_note[col]) |last_note| {
                                    note_ptr.* = makeSongNote(
                                        t,
                                        last_note.id,
                                        last_note.freq,
                                        false,
                                    );
                                    instrument_num_notes[instrument_index] += 1;
                                    column_last_note[col] = null;
                                }
                            },
                        }
                    }

                    t += NOTE_DURATION / (rate * tempo);

                    // sort the events at this time frame by note id. this
                    // puts note-offs before note-ons
                    var i: usize = 0;
                    while (i < NUM_INSTRUMENTS) : (i += 1) {
                        const start = old_instrument_num_notes[i];
                        const end = instrument_num_notes[i];
                        std.sort.sort(
                            zang.Notes(MyNoteParams).SongEvent,
                            all_notes_arr[i][start..end],
                            {},
                            struct {
                                fn compare(
                                    context: void,
                                    a: zang.Notes(MyNoteParams).SongEvent,
                                    b: zang.Notes(MyNoteParams).SongEvent,
                                ) bool {
                                    return a.note_id < b.note_id;
                                }
                            }.compare,
                        );
                    }
                },
                else => return error.BadToken,
            }
        }
    }

    // now for each of the 3 instruments, we have chronological list of all
    // note on and off events (with a lot of overlapping). the notes need to
    // be identified by their frequency, which kind of sucks. i should
    // probably change the parser above to assign them unique IDs.
    var i: usize = 0;
    while (i < NUM_INSTRUMENTS) : (i += 1) {
        all_notes[i] = all_notes_arr[i][0..instrument_num_notes[i]];
    }

    //i = 0; while (i < NUM_INSTRUMENTS) : (i += 1) {
    //    if (i == 1) {
    //        std.debug.warn("instrument {}:\n", .{ i });
    //        for (all_notes[i]) |note| {
    //            std.debug.warn("t={}  id={}  freq={}  note_on={}\n", .{
    //                note.t,
    //                note.id,
    //                note.params.freq,
    //                note.params.note_on,
    //            });
    //        }
    //    }
    //}
}

fn parse() void {
    var buffer: [150000]u8 = undefined;

    const contents = util.readFile(buffer[0..]) catch {
        std.debug.warn("failed to read file\n", .{});
        return;
    };

    var parser = Parser{
        .a4 = a4,
        .contents = contents,
        .index = 0,
        .line_index = 0,
    };

    doParse(&parser) catch {
        std.debug.warn("parse failed on line {}\n", .{parser.line_index + 1});
    };
}

// polyphonic instrument, encapsulating note tracking (uses `all_notes` global)
fn Voice(comptime T: type) type {
    return struct {
        pub const num_outputs = T.Module.num_outputs;
        pub const num_temps = T.Module.num_temps;

        const SubVoice = struct {
            module: T.Module,
            trigger: zang.Trigger(MyNoteParams),
        };

        tracker: zang.Notes(MyNoteParams).NoteTracker,
        dispatcher: zang.Notes(MyNoteParams).PolyphonyDispatcher(T.polyphony),

        sub_voices: [T.polyphony]SubVoice,

        fn init(track_index: usize) @This() {
            var self: @This() = .{
                .tracker = zang.Notes(MyNoteParams).NoteTracker.init(all_notes[track_index]),
                .dispatcher = zang.Notes(MyNoteParams).PolyphonyDispatcher(T.polyphony).init(),
                .sub_voices = undefined,
            };
            var i: usize = 0;
            while (i < T.polyphony) : (i += 1) {
                self.sub_voices[i] = .{
                    .module = T.initModule(),
                    .trigger = zang.Trigger(MyNoteParams).init(),
                };
            }
            return self;
        }

        fn reset(self: *@This()) void {
            self.tracker.reset();
            self.dispatcher.reset();
            for (self.sub_voices) |*sub_voice| {
                sub_voice.trigger.reset();
            }
        }

        fn paint(
            self: *@This(),
            span: zang.Span,
            outputs: [num_outputs][]f32,
            temps: [num_temps][]f32,
        ) void {
            const iap = self.tracker.consume(AUDIO_SAMPLE_RATE, span);

            const poly_iap = self.dispatcher.dispatch(iap);

            for (self.sub_voices) |*sub_voice, i| {
                var ctr = sub_voice.trigger.counter(span, poly_iap[i]);

                while (sub_voice.trigger.next(&ctr)) |result| {
                    sub_voice.module.paint(
                        result.span,
                        outputs,
                        temps,
                        result.note_id_changed,
                        T.makeParams(AUDIO_SAMPLE_RATE, result.params),
                    );
                }
            }
        }
    };
}

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = blk: {
        comptime var n: usize = 0;
        inline for (@typeInfo(Voices).Struct.fields) |field| {
            n = std.math.max(n, @field(field.field_type, "num_temps"));
        }
        break :blk n;
    };

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    voices: Voices,

    pub fn init() MainModule {
        parse();

        var mod: MainModule = .{
            .voices = undefined,
        };

        inline for (@typeInfo(Voices).Struct.fields) |field, track_index| {
            @field(mod.voices, field.name) =
                field.field_type.init(track_index);
        }

        return mod;
    }

    pub fn paint(
        self: *MainModule,
        span: zang.Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
    ) void {
        inline for (@typeInfo(Voices).Struct.fields) |field| {
            const VoiceType = field.field_type;
            @field(self.voices, field.name).paint(
                span,
                outputs,
                util.subarray(temps, VoiceType.num_temps),
            );
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        if (down and key == c.SDLK_SPACE) {
            inline for (@typeInfo(Voices).Struct.fields) |field| {
                @field(self.voices, field.name).reset();
            }
        }
        return false;
    }
};
