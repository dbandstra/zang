const note_frequencies = @import("zang-12tet");
pub const c = @import("common/c.zig");

pub const AudioOut = union(enum) {
    mono: usize,
    stereo: struct { left: usize, right: usize },
};

pub const Parameter = struct {
    desc: []const u8,
    num_values: u32,
    current_value: u32,
    favor_low_values: bool = false,
};

pub const KeyBinding = struct {
    row: u1,
    key: i32,
    rel_freq: f32,
};

// note: arpeggiator will cycle in this order, so i've arranged it from lowest
// frequency to highest
pub const key_bindings = [_]KeyBinding{
    // bottom two rows is one octave
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.b2, .key = c.SDLK_LSHIFT },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.c3, .key = c.SDLK_z },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.cs3, .key = c.SDLK_s },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.d3, .key = c.SDLK_x },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.ds3, .key = c.SDLK_d },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.e3, .key = c.SDLK_c },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.f3, .key = c.SDLK_v },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.fs3, .key = c.SDLK_g },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.g3, .key = c.SDLK_b },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.gs3, .key = c.SDLK_h },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.a3, .key = c.SDLK_n },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.as3, .key = c.SDLK_j },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.b3, .key = c.SDLK_m },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.c4, .key = c.SDLK_COMMA },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.cs4, .key = c.SDLK_l },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.d4, .key = c.SDLK_PERIOD },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.ds4, .key = c.SDLK_SEMICOLON },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.e4, .key = c.SDLK_SLASH },
    KeyBinding{ .row = 0, .rel_freq = note_frequencies.f4, .key = c.SDLK_RSHIFT },
    // top two rows is one octave up (with fair amount of overlap)
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.c4, .key = c.SDLK_q },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.cs4, .key = c.SDLK_2 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.d4, .key = c.SDLK_w },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.ds4, .key = c.SDLK_3 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.e4, .key = c.SDLK_e },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.f4, .key = c.SDLK_r },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.fs4, .key = c.SDLK_5 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.g4, .key = c.SDLK_t },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.gs4, .key = c.SDLK_6 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.a4, .key = c.SDLK_y },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.as4, .key = c.SDLK_7 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.b4, .key = c.SDLK_u },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.c5, .key = c.SDLK_i },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.cs5, .key = c.SDLK_9 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.d5, .key = c.SDLK_o },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.ds5, .key = c.SDLK_0 },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.e5, .key = c.SDLK_p },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.f5, .key = c.SDLK_LEFTBRACKET },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.fs5, .key = c.SDLK_EQUALS },
    KeyBinding{ .row = 1, .rel_freq = note_frequencies.g5, .key = c.SDLK_RIGHTBRACKET },
};

pub fn getKeyRelFreq(key: i32) ?f32 {
    for (key_bindings) |kb| {
        if (kb.key == key) {
            return kb.rel_freq;
        }
    }
    return null;
}

pub fn getKeyRelFreqFromRow(row: u1, key: i32) ?f32 {
    for (key_bindings) |kb| {
        if (kb.row == row and kb.key == key) {
            return kb.rel_freq;
        }
    }
    return null;
}
