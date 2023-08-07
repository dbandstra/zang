// this is a simple version of the Envelope

const zang = @import("zang");

pub const num_outputs = 1;
pub const num_temps = 0;
pub const Params = struct {
    note_on: bool,
};

pub fn init() @This() {
    return .{};
}

pub fn paint(
    self: *@This(),
    span: zang.Span,
    outputs: [num_outputs][]f32,
    temps: [num_temps][]f32,
    note_id_changed: bool,
    params: Params,
) void {
    _ = self;
    _ = temps;
    _ = note_id_changed;

    if (params.note_on) {
        zang.addScalarInto(span, outputs[0], 1.0);
    }
}
