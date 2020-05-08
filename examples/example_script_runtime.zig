const std = @import("std");
const zang = @import("zang");
const zangscript = @import("zangscript");
const common = @import("common.zig");
const c = @import("common/c.zig");
const modules = @import("modules.zig");

pub const AUDIO_FORMAT: zang.AudioFormat = .signed16_lsb;
pub const AUDIO_SAMPLE_RATE = 44100;
pub const AUDIO_BUFFER_SIZE = 1024;

pub const DESCRIPTION =
    \\example_script_runtime
    \\
    \\Play a scripted sound module with the keyboard.
    \\
    \\Press Enter to reload the script.
;

const a4 = 440.0;
const polyphony = 8;

const custom_builtin_package = zangscript.BuiltinPackage{
    .zig_package_name = "modules",
    .zig_import_path = "modules.zig",
    .builtins = &[_]zangscript.BuiltinModule{
        zangscript.getBuiltinModule(modules.FilteredSawtoothInstrument),
    },
    .enums = &[_]zangscript.BuiltinEnum{},
};

const builtin_packages = [_]zangscript.BuiltinPackage{
    zangscript.zang_builtin_package,
    custom_builtin_package,
};

pub const MainModule = struct {
    // FIXME (must be at least as many outputs/temps are used in the script)
    // to fix this i would have to change the interface of all example MainModules to be something more dynamic
    pub const num_outputs = 1;
    pub const num_temps = 20;

    const filename = "examples/script.txt";
    const module_name = "Instrument";
    const Params = struct {
        sample_rate: f32,
        freq: zang.ConstantOrBuffer,
        note_on: bool,
    };

    const Voice = struct {
        module: *zangscript.ModuleBase,
        trigger: zang.Trigger(Params),
    };

    allocator: *std.mem.Allocator,
    contents: []const u8,
    script: *zangscript.CompiledScript,

    dispatcher: zang.Notes(Params).PolyphonyDispatcher(polyphony),
    voices: [polyphony]Voice,

    note_ids: [common.key_bindings.len]?usize,
    next_note_id: usize,

    iq: zang.Notes(Params).ImpulseQueue,

    pub fn init() !MainModule {
        var allocator = std.heap.page_allocator;

        const contents = try std.fs.cwd().readFileAlloc(allocator, filename, 16 * 1024 * 1024);
        errdefer allocator.free(contents);

        var script = try zangscript.compile(filename, contents, &builtin_packages, allocator);
        errdefer script.deinit();

        var script_ptr = try allocator.create(zangscript.CompiledScript);
        script_ptr.* = script;

        const module_index = for (script.modules) |module, i| {
            if (std.mem.eql(u8, module.name, module_name)) break i;
        } else return error.ModuleNotFound;

        var self: MainModule = .{
            .allocator = allocator,
            .contents = contents,
            .script = script_ptr,
            .note_ids = [1]?usize{null} ** common.key_bindings.len,
            .next_note_id = 1,
            .iq = zang.Notes(Params).ImpulseQueue.init(),
            .dispatcher = zang.Notes(Params).PolyphonyDispatcher(polyphony).init(),
            .voices = undefined,
        };
        var num_voices_initialized: usize = 0;
        errdefer for (self.voices[0..num_voices_initialized]) |*voice| {
            voice.module.deinit();
        };
        for (self.voices) |*voice| {
            voice.* = .{
                .module = try zangscript.initModule(script_ptr, module_index, &builtin_packages, allocator),
                .trigger = zang.Trigger(Params).init(),
            };
            num_voices_initialized += 1;
        }
        return self;
    }

    pub fn deinit(self: *MainModule) void {
        for (self.voices) |*voice| {
            voice.module.deinit();
        }
        self.script.deinit();
        self.allocator.destroy(self.script);
        self.allocator.free(self.contents);
    }

    pub fn paint(self: *MainModule, span: zang.Span, outputs: [num_outputs][]f32, temps: [num_temps][]f32) void {
        const iap = self.iq.consume();

        const poly_iap = self.dispatcher.dispatch(iap);

        for (self.voices) |*voice, i| {
            var ctr = voice.trigger.counter(span, poly_iap[i]);
            while (voice.trigger.next(&ctr)) |result| {
                const params = voice.module.makeParams(Params, result.params) orelse return;
                // script modules zero out their output before writing, so i need a temp to accumulate the outputs
                zang.zero(result.span, temps[0]);
                voice.module.paint(
                    result.span,
                    temps[0..1],
                    temps[1 .. voice.module.num_temps + 1],
                    result.note_id_changed,
                    &params,
                );
                zang.addInto(result.span, outputs[0], temps[0]);
            }
        }
    }

    pub fn keyEvent(self: *MainModule, key: i32, down: bool, impulse_frame: usize) bool {
        for (common.key_bindings) |kb, i| {
            if (kb.key != key) {
                continue;
            }

            const params: Params = .{
                .sample_rate = AUDIO_SAMPLE_RATE,
                .freq = zang.constant(a4 * kb.rel_freq),
                .note_on = down,
            };

            if (down) {
                if (self.note_ids[i] == null) {
                    self.iq.push(impulse_frame, self.next_note_id, params);
                    self.note_ids[i] = self.next_note_id;
                    self.next_note_id += 1;
                }
            } else if (self.note_ids[i]) |note_id| {
                self.iq.push(impulse_frame, note_id, params);
                self.note_ids[i] = null;
            }
        }
        return true;
    }
};
