const std = @import("std");

pub const Span = struct {
    start: usize,
    end: usize,

    pub inline fn init(start: usize, end: usize) Span {
        return .{ .start = start, .end = end };
    }
};

pub fn zero(span: Span, dest: []f32) void {
    @memset(dest[span.start..span.end], 0.0);
}

pub fn set(span: Span, dest: []f32, a: f32) void {
    @memset(dest[span.start..span.end], a);
}

pub fn copy(span: Span, dest: []f32, src: []const f32) void {
    @memcpy(dest[span.start..span.end], src[span.start..span.end]);
}

pub fn add(span: Span, dest: []f32, a: []const f32, b: []const f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] += a[i] + b[i];
    }
}

pub fn addInto(span: Span, dest: []f32, src: []const f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] += src[i];
    }
}

pub fn addScalar(span: Span, dest: []f32, a: []const f32, b: f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] += a[i] + b;
    }
}

pub fn addScalarInto(span: Span, dest: []f32, a: f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] += a;
    }
}

pub fn multiply(span: Span, dest: []f32, a: []const f32, b: []const f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] += a[i] * b[i];
    }
}

pub fn multiplyWith(span: Span, dest: []f32, a: []const f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] *= a[i];
    }
}

pub fn multiplyScalar(span: Span, dest: []f32, a: []const f32, b: f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] += a[i] * b;
    }
}

pub fn multiplyWithScalar(span: Span, dest: []f32, a: f32) void {
    var i = span.start;
    while (i < span.end) : (i += 1) {
        dest[i] *= a;
    }
}
