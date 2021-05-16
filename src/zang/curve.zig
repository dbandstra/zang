// this is used by modules/Curve.zig, but it's in "zang" because the scripting
// language is aware of it.
pub const CurveNode = struct {
    value: f32,
    t: f32,
};
