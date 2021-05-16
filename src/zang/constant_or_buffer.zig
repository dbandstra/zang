// some modules may have optimized paint paths if an input is known to be a
// constant. in that case, use ConstantOrBuffer as the param type.

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
