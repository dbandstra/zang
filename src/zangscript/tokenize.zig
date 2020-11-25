const std = @import("std");
const Context = @import("context.zig").Context;
const SourceLocation = @import("context.zig").SourceLocation;
const SourceRange = @import("context.zig").SourceRange;
const fail = @import("fail.zig").fail;

pub const TokenType = union(enum) {
    illegal,
    end_of_file,
    name,
    number: f32,
    enum_value,
    sym_asterisk,
    sym_colon,
    sym_comma,
    sym_equals,
    sym_left_paren,
    sym_minus,
    sym_plus,
    sym_right_paren,
    sym_slash,
    kw_begin,
    kw_defcurve,
    kw_defmodule,
    kw_deftrack,
    kw_delay,
    kw_end,
    kw_false,
    kw_feedback,
    kw_from,
    kw_out,
    kw_true,
};

pub const Token = struct {
    source_range: SourceRange,
    tt: TokenType,
};

pub const Tokenizer = struct {
    ctx: Context,
    loc: SourceLocation,

    pub fn init(ctx: Context) Tokenizer {
        return .{
            .ctx = ctx,
            .loc = .{ .line = 0, .index = 0 },
        };
    }

    fn makeToken(loc0: SourceLocation, loc1: SourceLocation, tt: TokenType) Token {
        return .{
            .source_range = .{ .loc0 = loc0, .loc1 = loc1 },
            .tt = tt,
        };
    }

    pub fn next(self: *Tokenizer) !Token {
        const src = self.ctx.source.contents;

        var loc = self.loc;
        defer self.loc = loc;

        while (true) {
            while (loc.index < src.len and isWhitespace(src[loc.index])) {
                if (src[loc.index] == '\r') {
                    loc.index += 1;
                    if (loc.index == src.len or src[loc.index] != '\n') {
                        loc.line += 1;
                        continue;
                    }
                }
                if (src[loc.index] == '\n') {
                    loc.line += 1;
                }
                loc.index += 1;
            }
            if (loc.index + 2 < src.len and src[loc.index] == '/' and src[loc.index + 1] == '/') {
                while (loc.index < src.len and src[loc.index] != '\r' and src[loc.index] != '\n') {
                    loc.index += 1;
                }
                continue;
            }
            if (loc.index == src.len) {
                return makeToken(loc, loc, .end_of_file);
            }
            const start = loc;
            inline for (@typeInfo(TokenType).Union.fields) |field| {
                if (comptime std.mem.startsWith(u8, field.name, "sym_")) {
                    const tt = @unionInit(TokenType, field.name, {});
                    const symbol_string = getSymbolString(tt);
                    if (std.mem.startsWith(u8, src[loc.index..], symbol_string)) {
                        loc.index += symbol_string.len;
                        return makeToken(start, loc, tt);
                    }
                }
            }
            if (src[loc.index] == '.') {
                loc.index += 1;
                const start2 = loc;
                if (loc.index == src.len or !isValidNameHeadChar(src[loc.index])) {
                    const sr: SourceRange = .{ .loc0 = start, .loc1 = start2 };
                    return fail(self.ctx, sr, "dot must be followed by an identifier", .{});
                }
                loc.index += 1;
                while (loc.index < src.len and isValidNameTailChar(src[loc.index])) {
                    loc.index += 1;
                }
                return makeToken(start2, loc, .enum_value);
            }
            if (getNumber(src[loc.index..])) |len| {
                loc.index += len;
                const n = std.fmt.parseFloat(f32, src[start.index..loc.index]) catch {
                    const sr: SourceRange = .{ .loc0 = start, .loc1 = loc };
                    return fail(self.ctx, sr, "malformatted number", .{});
                };
                return makeToken(start, loc, .{ .number = n });
            }
            if (isValidNameHeadChar(src[loc.index])) {
                loc.index += 1;
                while (loc.index < src.len and isValidNameTailChar(src[loc.index])) {
                    loc.index += 1;
                }
                const string = src[start.index..loc.index];
                inline for (@typeInfo(TokenType).Union.fields) |field| {
                    if (comptime std.mem.startsWith(u8, field.name, "kw_")) {
                        const tt = @unionInit(TokenType, field.name, {});
                        if (std.mem.eql(u8, string, getKeywordString(tt))) {
                            return makeToken(start, loc, tt);
                        }
                    }
                }
                return makeToken(start, loc, .name);
            }
            loc.index += 1;
            return makeToken(start, loc, .illegal);
        }
    }

    pub fn peek(self: *Tokenizer) !Token {
        const loc = self.loc;
        defer self.loc = loc;

        return try self.next();
    }

    pub fn failExpected(self: *Tokenizer, desc: []const u8, found: Token) error{Failed} {
        if (found.tt == .end_of_file) {
            return fail(self.ctx, found.source_range, "expected #, found end of file", .{desc});
        } else {
            return fail(self.ctx, found.source_range, "expected #, found `<`", .{desc});
        }
    }

    // use this for requiring the next token to be a specific symbol or keyword
    pub fn expectNext(self: *Tokenizer, tt: anytype) !void {
        const token = try self.next();
        if (token.tt == tt) return;
        const desc = if (comptime std.mem.startsWith(u8, @tagName(tt), "sym_"))
            "`" ++ getSymbolString(tt) ++ "`"
        else if (comptime std.mem.startsWith(u8, @tagName(tt), "kw_"))
            "`" ++ getKeywordString(tt) ++ "`"
        else
            unreachable;
        return self.failExpected(desc, token);
    }
};

inline fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

// leading underscore is not allowed
inline fn isValidNameHeadChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

inline fn isValidNameTailChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_';
}

fn getNumber(string: []const u8) ?usize {
    if (string[0] >= '0' and string[0] <= '9') {
        var i: usize = 1;
        while (i < string.len and ((string[i] >= '0' and string[i] <= '9') or string[i] == '.')) {
            i += 1;
        }
        return i;
    }
    return null;
}

fn getSymbolString(tt: TokenType) []const u8 {
    switch (tt) {
        .sym_asterisk => return "*",
        .sym_colon => return ":",
        .sym_comma => return ",",
        .sym_equals => return "=",
        .sym_left_paren => return "(",
        .sym_minus => return "-",
        .sym_plus => return "+",
        .sym_right_paren => return ")",
        .sym_slash => return "/",
        else => unreachable,
    }
}

fn getKeywordString(tt: TokenType) []const u8 {
    switch (tt) {
        .kw_begin => return "begin",
        .kw_defcurve => return "defcurve",
        .kw_defmodule => return "defmodule",
        .kw_deftrack => return "deftrack",
        .kw_delay => return "delay",
        .kw_end => return "end",
        .kw_false => return "false",
        .kw_feedback => return "feedback",
        .kw_from => return "from",
        .kw_out => return "out",
        .kw_true => return "true",
        else => unreachable,
    }
}
