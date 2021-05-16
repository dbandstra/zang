const std = @import("std");
const zang = @import("../zang.zig");
const mod = @import("../modules.zig");
const ModuleParam = @import("parse.zig").ModuleParam;
const ParamType = @import("parse.zig").ParamType;

pub const BuiltinModule = struct {
    name: []const u8,
    params: []const ModuleParam,
    num_temps: usize,
    num_outputs: usize,
};

pub const BuiltinEnum = struct {
    name: []const u8,
    zig_name: []const u8,
    values: []const BuiltinEnumValue,
};

pub const BuiltinEnumValue = struct {
    label: []const u8,
    payload_type: enum { none, f32 },
};

fn getBuiltinEnumFromEnumInfo(
    name: []const u8,
    zig_name: []const u8,
    comptime enum_info: std.builtin.TypeInfo.Enum,
) BuiltinEnum {
    comptime var values: [enum_info.fields.len]BuiltinEnumValue = undefined;
    inline for (enum_info.fields) |field, i| {
        values[i].label = field.name;
        values[i].payload_type = .none;
    }
    return .{
        .name = name,
        .zig_name = zig_name,
        .values = &values,
    };
}

fn getBuiltinEnumFromUnionInfo(
    name: []const u8,
    zig_name: []const u8,
    comptime union_info: std.builtin.TypeInfo.Union,
) BuiltinEnum {
    comptime var values: [union_info.fields.len]BuiltinEnumValue = undefined;
    inline for (union_info.fields) |field, i| {
        values[i].label = field.name;
        values[i].payload_type = switch (field.field_type) {
            void => .none,
            f32 => .f32,
            else => @compileError("getBuiltinEnumFromUnionInfo: unsupported field_type: " ++ @typeName(field.field_type)),
        };
    }
    return .{
        .name = name,
        .zig_name = zig_name,
        .values = &values,
    };
}

fn getBuiltinEnum(comptime T: type) BuiltinEnum {
    var name: []const u8 = undefined;
    var zig_name: []const u8 = undefined;

    switch (T) {
        zang.PaintCurve => {
            name = "PaintCurve";
            zig_name = "zang.PaintCurve";
        },
        mod.Curve.InterpolationFunction => {
            name = "InterpolationFunction";
            zig_name = "mod.Curve.InterpolationFunction";
        },
        mod.Distortion.Type => {
            name = "DistortionType";
            zig_name = "mod.Distortion.Type";
        },
        mod.Filter.Type => {
            name = "FilterType";
            zig_name = "mod.Filter.Type";
        },
        mod.Noise.Color => {
            name = "NoiseColor";
            zig_name = "mod.Noise.Color";
        },
        else => @compileError("unsupported enum: " ++ @typeName(T)),
    }

    switch (@typeInfo(T)) {
        .Enum => |enum_info| return getBuiltinEnumFromEnumInfo(name, zig_name, enum_info),
        .Union => |union_info| return getBuiltinEnumFromUnionInfo(name, zig_name, union_info),
        else => @compileError("getBuiltinEnum: not an enum: " ++ zig_name),
    }
}

// this also reads enums, separately from the global list of enums that we get for the builtin package.
// but it's ok because zangscript compares enums "structurally".
// (although i don't think zig does. so this might create zig errors if i try to codegen something
// that uses enums with overlapping value names. not important now though because user-defined enums
// are currently not supported, and so far no builtins have overlapping enums)
fn getBuiltinParamType(comptime T: type) ParamType {
    return switch (T) {
        bool => .boolean,
        f32 => .constant,
        []const f32 => .buffer,
        zang.ConstantOrBuffer => .constant_or_buffer,
        []const mod.Curve.Node => .curve,
        else => switch (@typeInfo(T)) {
            .Enum, .Union => return .{ .one_of = getBuiltinEnum(T) },
            else => @compileError("unsupported builtin field type: " ++ @typeName(T)),
        },
    };
}

pub fn getBuiltinModule(comptime T: type) BuiltinModule {
    const struct_fields = @typeInfo(T.Params).Struct.fields;
    comptime var params: [struct_fields.len]ModuleParam = undefined;
    inline for (struct_fields) |field, i| {
        params[i] = .{
            .name = field.name,
            .param_type = getBuiltinParamType(field.field_type),
        };
    }
    return .{
        .name = @typeName(T),
        .params = &params,
        .num_temps = T.num_temps,
        .num_outputs = T.num_outputs,
    };
}

pub const BuiltinPackage = struct {
    zig_package_name: []const u8,
    zig_import_path: []const u8, // relative to zang root dir
    builtins: []const BuiltinModule,
    enums: []const BuiltinEnum,
};

pub const zang_builtin_package = BuiltinPackage{
    .zig_package_name = "zang",
    .zig_import_path = "zang",
    .builtins = &[_]BuiltinModule{},
    .enums = &[_]BuiltinEnum{
        getBuiltinEnum(zang.PaintCurve),
    },
};

pub const modules_builtin_package = BuiltinPackage{
    .zig_package_name = "mod",
    .zig_import_path = "modules",
    .builtins = &[_]BuiltinModule{
        getBuiltinModule(mod.Curve),
        getBuiltinModule(mod.Cycle),
        getBuiltinModule(mod.Decimator),
        getBuiltinModule(mod.Distortion),
        getBuiltinModule(mod.Envelope),
        getBuiltinModule(mod.Filter),
        getBuiltinModule(mod.Gate),
        getBuiltinModule(mod.Noise),
        getBuiltinModule(mod.Portamento),
        getBuiltinModule(mod.PulseOsc),
        // mod.Sampler
        getBuiltinModule(mod.SineOsc),
        getBuiltinModule(mod.TriSawOsc),
    },
    .enums = &[_]BuiltinEnum{
        getBuiltinEnum(mod.Curve.InterpolationFunction),
        getBuiltinEnum(mod.Distortion.Type),
        getBuiltinEnum(mod.Filter.Type),
        getBuiltinEnum(mod.Noise.Color),
    },
};
