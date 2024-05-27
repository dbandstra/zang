// "proper" polyphony (example_polyphony.zig is a more brute force method)
// this method uses a static number of voice "slots", which are recycled

const zang = @import("zang");
const common = @import("common");
const c = common.c;
const Module = @import("modules.zig").NiceInstrument;

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 48000;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_polyphony2
    \\
    \\Play an instrument with the keyboard. There are 3
    \\voice slots.
;

const a4 = 220.0;
const polyphony = 3;

pub const MainModule = struct {
    pub const num_outputs = 1;
    pub const num_temps = 2;

    pub const output_audio = common.AudioOut{ .mono = 0 };
    pub const output_visualize = 0;

    const Voice = struct {
        module: Module,
        trigger: zang.Trigger(Module.Params),
    };

    dispatcher: zang.Notes(Module.Params).PolyphonyDispatcher(polyphony),
    voices: [polyphony]Voice,

    note_ids: [common.key_bindings.len]?usize,
    next_note_id: usize,

    iq: zang.Notes(Module.Params).ImpulseQueue,

    pub fn init() MainModule {
        var self: MainModule = .{
            .note_ids = [1]?usize{null} ** common.key_bindings.len,
            .next_note_id = 1,
            .iq = zang.Notes(Module.Params).ImpulseQueue.init(),
            .dispatcher = zang.Notes(Module.Params).PolyphonyDispatcher(polyphony).init(),
            .voices = undefined,
        };
        var i: usize = 0;
        while (i < polyphony) : (i += 1) {
            self.voices[i] = .{
                .module = Module.init(0.3),
                .trigger = zang.Trigger(Module.Params).init(),
            };
        }
        return self;
    }

    pub fn paint(self: *MainModule, span: zang.Span, outputs: [num_outputs][]f32, temps: [num_temps][]f32) void {
        const iap = self.iq.consume();

        const poly_iap = self.dispatcher.dispatch(iap);

        for (&self.voices, 0..) |*voice, i| {
            var ctr = voice.trigger.counter(span, poly_iap[i]);
            while (voice.trigger.next(&ctr)) |result| {
                voice.module.paint(result.span, outputs, temps, result.note_id_changed, result.params);
            }
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        for (common.key_bindings, 0..) |kb, i| {
            if (kb.key != key) {
                continue;
            }

            const params: Module.Params = .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .freq = a4 * kb.rel_freq,
                .note_on = down,
            };

            if (down) {
                self.iq.push(impulse_frame, self.next_note_id, params);
                self.note_ids[i] = self.next_note_id;
                self.next_note_id += 1;
            } else if (self.note_ids[i]) |note_id| {
                self.iq.push(impulse_frame, note_id, params);
                self.note_ids[i] = null;
            }
        }
        return true;
    }
};
