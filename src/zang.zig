const notes = @import("zang/notes.zig");
pub const IdGenerator = notes.IdGenerator;
pub const Impulse = notes.Impulse;
pub const Notes = notes.Notes;

const trigger = @import("zang/trigger.zig");
pub const ConstantOrBuffer = trigger.ConstantOrBuffer;
pub const constant = trigger.constant;
pub const buffer = trigger.buffer;
pub const Trigger = trigger.Trigger;

const mixdown = @import("zang/mixdown.zig");
pub const AudioFormat = mixdown.AudioFormat;
pub const mixDown = mixdown.mixDown;

const basics = @import("zang/basics.zig");
pub const Span = basics.Span;
pub const zero = basics.zero;
pub const set = basics.set;
pub const copy = basics.copy;
pub const add = basics.add;
pub const addInto = basics.addInto;
pub const addScalar = basics.addScalar;
pub const addScalarInto = basics.addScalarInto;
pub const multiply = basics.multiply;
pub const multiplyWith = basics.multiplyWith;
pub const multiplyScalar = basics.multiplyScalar;
pub const multiplyWithScalar = basics.multiplyWithScalar;

const painter = @import("zang/painter.zig");
pub const PaintCurve = painter.PaintCurve;
pub const PaintState = painter.PaintState;
pub const Painter = painter.Painter;

const delay = @import("zang/delay.zig");
pub const Delay = delay.Delay;

const curve = @import("zang/curve.zig");
pub const CurveNode = curve.CurveNode;
