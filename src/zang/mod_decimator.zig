const Span = @import("basics.zig").Span;
const addInto = @import("basics.zig").addInto;

pub const Decimator = struct {
    pub const num_outputs = 1;
    pub const num_temps = 0;
    pub const Params = struct {
        sample_rate: f32,
        input: []const f32,
        fake_sample_rate: f32,
    };

    dval: f32,
    dcount: f32,

    pub fn init() Decimator {
        return .{
            .dval = 0.0,
            .dcount = 1.0,
        };
    }

    pub fn paint(
        self: *Decimator,
        span: Span,
        outputs: [num_outputs][]f32,
        temps: [num_temps][]f32,
        note_id_changed: bool,
        params: Params,
    ) void {
        const output = outputs[0];

        if (params.fake_sample_rate >= params.sample_rate) {
            addInto(span, output, params.input);

            self.dval = 0.0;
            self.dcount = 1.0;
        } else if (params.fake_sample_rate > 0.0) {
            const ratio = params.fake_sample_rate / params.sample_rate;
            var dcount = self.dcount;
            var dval = self.dval;

            var i = span.start;
            while (i < span.end) : (i += 1) {
                dcount += ratio;
                if (dcount >= 1.0) {
                    dval = params.input[i];
                    dcount -= 1.0;
                }
                output[i] += dval;
            }

            self.dcount = dcount;
            self.dval = dval;
        }
    }
};
