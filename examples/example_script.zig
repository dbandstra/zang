const std = @import("std");
const zang = @import("zang");
const note_frequencies = @import("zang-12tet");
const common = @import("common");
const c = common.c;
const DemoPlayer = @import("scriptgen.zig").DemoPlayer;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 44100;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_script
    \\
    \\Play a scripted sound module with the keyboard.
;

const a4 = 440.0;

pub const MainModule = struct {
    comptime {
        std.debug.assert(DemoPlayer.num_outputs == 1);
    }
    pub const num_outputs = 2;
    pub const num_temps = DemoPlayer.num_temps;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;
    pub const output_sync_oscilloscope = 1;

    key: ?i32,
    iq: zang.Notes(DemoPlayer.Params).ImpulseQueue,
    idgen: zang.IdGenerator,
    instr: DemoPlayer,
    trig: zang.Trigger(DemoPlayer.Params),

    pub fn init() MainModule {
        return .{
            .key = null,
            .iq = zang.Notes(DemoPlayer.Params).ImpulseQueue.init(),
            .idgen = zang.IdGenerator.init(),
            .instr = DemoPlayer.init(),
            .trig = zang.Trigger(DemoPlayer.Params).init(),
        };
    }

    pub fn paint(self: *MainModule, span: zang.Span, outputs: [num_outputs][]f32, temps: [num_temps][]f32) void {
        var ctr = self.trig.counter(span, self.iq.consume());
        while (self.trig.next(&ctr)) |result| {
            self.instr.paint(result.span, .{outputs[0]}, temps, result.note_id_changed, result.params);
            switch (result.params.freq) {
                .constant => |freq| zang.addScalarInto(result.span, outputs[1], freq),
                .buffer => |freq| zang.addInto(result.span, outputs[1], freq),
            }
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        const rel_freq = common.getKeyRelFreq(key) orelse return false;
        if (down or (if (self.key) |nh| nh == key else false)) {
            self.key = if (down) key else null;
            self.iq.push(impulse_frame, self.idgen.nextId(), .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .freq = zang.constant(a4 * rel_freq),
                .note_on = down,
            });
        }
        return true;
    }
};
