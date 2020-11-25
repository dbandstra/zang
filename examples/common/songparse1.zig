const std = @import("std");

pub fn Parser(comptime num_columns: usize) type {
    return struct {
        pub const Note = union(enum) {
            idle: void,
            freq: f32,
            off: void,
        };

        pub const Token = union(enum) {
            word: []const u8,
            number: f32,
            notes: [num_columns]Note,

            pub fn isWord(token: Token, word: []const u8) bool {
                return switch (token) {
                    .word => |s| std.mem.eql(u8, word, s),
                    else => false,
                };
            }
        };

        a4: f32,
        contents: []const u8,
        index: usize,
        line_index: usize,

        fn parseNote(parser: *@This()) ?f32 {
            if (parser.index + 3 > parser.contents.len) {
                return null;
            }

            const letter = parser.contents[parser.index];
            const modifier = parser.contents[parser.index + 1];
            const octave = parser.contents[parser.index + 2];

            const offset = if (octave >= '0' and octave <= '9')
                @intCast(i32, octave - '0') * 12 - 57
            else
                return null;

            const semitone: i32 = blk: {
                if (letter == 'C' and modifier == '-') break :blk 0;
                if (letter == 'C' and modifier == '#') break :blk 1;
                if (letter == 'D' and modifier == '-') break :blk 2;
                if (letter == 'D' and modifier == '#') break :blk 3;
                if (letter == 'E' and modifier == '-') break :blk 4;
                if (letter == 'F' and modifier == '-') break :blk 5;
                if (letter == 'F' and modifier == '#') break :blk 6;
                if (letter == 'G' and modifier == '-') break :blk 7;
                if (letter == 'G' and modifier == '#') break :blk 8;
                if (letter == 'A' and modifier == '-') break :blk 9;
                if (letter == 'A' and modifier == '#') break :blk 10;
                if (letter == 'B' and modifier == '-') break :blk 11;
                return null;
            };

            parser.index += 3;

            const exp = @intToFloat(f32, offset + semitone) / 12.0;
            return parser.a4 * std.math.pow(f32, 2.0, exp);
        }

        pub fn eat(parser: *@This(), prefix: []const u8) bool {
            const contents = parser.contents[parser.index..];
            if (!std.mem.startsWith(u8, contents, prefix)) {
                return false;
            }
            parser.index += prefix.len;
            return true;
        }

        pub fn parseToken(parser: *@This()) !?Token {
            while (true) {
                if (parser.eat(" ")) {
                    // pass
                } else if (parser.eat("\n")) {
                    parser.line_index += 1;
                } else if (parser.eat("#")) {
                    const contents = parser.contents[parser.index..];
                    if (std.mem.indexOfScalar(u8, contents, '\n')) |pos| {
                        parser.line_index += 1;
                        parser.index += pos + 1;
                    } else {
                        parser.index = parser.contents.len;
                    }
                } else {
                    break;
                }
            }

            if (parser.index >= parser.contents.len) {
                return null;
            }

            const ch = parser.contents[parser.index];

            if (ch == '|') {
                parser.index += 1;

                var notes = [1]Note{.idle} ** num_columns;

                var col: usize = 0;
                while (true) : (col += 1) {
                    if (col >= num_columns) {
                        return error.SyntaxError;
                    }

                    if (parseNote(parser)) |freq| {
                        notes[col] = .{ .freq = freq };
                    } else if (parser.eat("off")) {
                        notes[col] = .off;
                    } else if (parser.eat("   ")) {
                        // pass
                    } else {
                        break;
                    }

                    if (parser.index < parser.contents.len and
                        (parser.contents[parser.index] == ' ' or
                        parser.contents[parser.index] == '|'))
                    {
                        parser.index += 1;
                    } else {
                        break;
                    }
                }

                if (parser.index < parser.contents.len) {
                    if (parser.contents[parser.index] == '\n') {
                        parser.line_index += 1;
                        parser.index += 1;
                    } else {
                        return error.SyntaxError;
                    }
                }

                return Token{ .notes = notes };
            }

            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or ch == '_')
            {
                const start = parser.index;
                parser.index += 1;
                while (parser.index < parser.contents.len) {
                    const ch2 = parser.contents[parser.index];
                    if ((ch2 >= 'a' and ch2 <= 'z') or
                        (ch2 >= 'A' and ch2 <= 'Z') or
                        (ch2 >= '0' and ch2 <= '9') or ch2 == '_')
                    {
                        parser.index += 1;
                    } else {
                        break;
                    }
                }
                return Token{ .word = parser.contents[start..parser.index] };
            }

            if (ch >= '0' and ch <= '9') {
                const start = parser.index;
                var dot = false;
                parser.index += 1;
                while (parser.index < parser.contents.len) {
                    const ch2 = parser.contents[parser.index];
                    if (ch2 == '.') {
                        if (dot) {
                            break;
                        } else {
                            dot = true;
                            parser.index += 1;
                        }
                    } else if (ch2 >= '0' and ch2 <= '9') {
                        parser.index += 1;
                    } else {
                        break;
                    }
                }
                const number = try std.fmt.parseFloat(f32, parser.contents[start..parser.index]);
                return Token{ .number = number };
            }

            return error.SyntaxError;
        }

        fn requireToken(parser: *@This()) !Token {
            return (try parser.parseToken()) orelse error.UnexpectedEof;
        }

        pub fn requireNumber(parser: *@This()) !f32 {
            return switch (try parser.requireToken()) {
                .number => |n| n,
                else => error.ExpectedNumber,
            };
        }
    };
}
