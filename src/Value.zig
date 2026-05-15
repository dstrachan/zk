const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zk = @import("root.zig");
const Vm = zk.Vm;

const Value = @This();

ref_count: u32 = 0,
as: Union,

pub fn ref(value: *Value) *Value {
    value.ref_count += 1;
    return value;
}

pub fn deref(value: *Value, gpa: Allocator) void {
    if (value.ref_count > 0) {
        value.ref_count -= 1;
    } else {
        switch (value.as) {
            .list => |list| {
                for (list) |v| v.deref(gpa);
                gpa.free(list);
            },
            .boolean => {},
            .boolean_list => |list| gpa.free(list),
            .long => {},
            .long_list => |list| gpa.free(list),
            .float => {},
            .float_list => |list| gpa.free(list),
            .char => {},
            .char_list => |list| gpa.free(list),
            .symbol => {},
            .symbol_list => |list| gpa.free(list),
            .dict => |val| {
                val.keys.deref(gpa);
                val.values.deref(gpa);
            },
            .lambda => |val| {
                gpa.free(val.bytecode);
                gpa.free(val.params);
                gpa.free(val.locals);
                gpa.free(val.globals);
                for (val.constants) |v| v.deref(gpa);
                gpa.free(val.constants);
                gpa.free(val.source);
            },
            .unary_primitive => {},
            .operator => {},
            .projection => |val| {
                val.callee.deref(gpa);
                for (val.args) |v| v.deref(gpa);
                gpa.free(val.args);
            },
        }
        gpa.destroy(value);
    }
}

pub fn format(self: *Value, w: *Io.Writer, vm: *Vm) !void {
    switch (self.as) {
        .list => |value| {
            if (value.len == 1) {
                try w.print(",{f}", .{value[0].alt(vm)});
            } else {
                try w.writeByte('(');
                if (value.len > 0) {
                    try w.print("{f}", .{value[0].alt(vm)});
                    for (value[1..]) |v| try w.print(";{f}", .{v.alt(vm)});
                }
                try w.writeByte(')');
            }
        },
        .boolean => |value| try w.print("{d}b", .{@intFromBool(value)}),
        .boolean_list => |value| {
            if (value.len == 0) {
                try w.writeAll("`boolean$()");
            } else {
                for (value) |v| try w.print("{d}", .{@intFromBool(v)});
                try w.writeByte('b');
            }
        },
        .long => |value| {
            const long: Long = @enumFromInt(value);
            try w.print("{f}", .{long});
        },
        .long_list => |value| {
            if (value.len == 0) {
                try w.writeAll("`long$()");
            } else {
                const long_list: []Long = @ptrCast(value);
                try w.print("{f}", .{long_list[0]});
                for (long_list[1..]) |v| try w.print(" {f}", .{v});
            }
        },
        .float => |value| try w.print("{d}f", .{value}),
        .float_list => |value| {
            if (value.len == 0) {
                try w.writeAll("`float$()");
            } else {
                try w.print("{d}", .{value[0]});
                for (value[1..]) |v| try w.print(" {d}", .{v});
                try w.writeByte('f');
            }
        },
        .char => |value| try w.print("\"{c}\"", .{value}),
        .char_list => |value| {
            if (value.len == 1) try w.writeByte(',');
            try w.writeByte('"');
            for (value) |b| switch (b) {
                '\n' => try w.writeAll("\\n"),
                '\r' => try w.writeAll("\\r"),
                '\t' => try w.writeAll("\\t"),
                '\\' => try w.writeAll("\\\\"),
                '"' => try w.writeAll("\\\""),
                ' ', '!', '#'...'[', ']'...'~' => try w.writeByte(b),
                else => unreachable, // TODO: Implement octal characters in tokenizer
            };
            try w.writeByte('"');
        },
        .symbol => |value| try w.print("`{s}", .{vm.internedString(value)}),
        .symbol_list => |value| {
            if (value.len == 0) {
                try w.writeAll("`symbol$()");
            } else {
                if (value.len == 1) try w.writeByte(',');
                for (value) |v| try w.print("`{s}", .{vm.internedString(v)});
            }
        },
        .dict => |value| {
            if (value.keys.count() <= 1) {
                try w.print("({f})!{f}", .{ value.keys.alt(vm), value.values.alt(vm) });
            } else {
                try w.print("{f}!{f}", .{ value.keys.alt(vm), value.values.alt(vm) });
            }
        },
        .lambda => |value| try w.print("{s}", .{value.source}),
        .unary_primitive => |value| try w.print("{f}", .{value}),
        .operator => |value| try w.print("{f}", .{value}),
        .projection => |value| {
            try w.print("{f}", .{value.callee.alt(vm)});
            try w.writeByte('[');
            if (value.args[0].as != .unary_primitive or value.args[0].as.unary_primitive != .empty) {
                try w.print("{f}", .{value.args[0].alt(vm)});
            }
            for (value.args[1..]) |a| {
                try w.writeByte(';');
                if (a.as != .unary_primitive or a.as.unary_primitive != .empty) try w.print("{f}", .{a.alt(vm)});
            }
            try w.writeByte(']');
        },
    }
}

pub const Alt = struct {
    vm: *Vm,
    value: *Value,

    pub fn format(data: @This(), w: *Io.Writer) Io.Writer.Error!void {
        try data.value.format(w, data.vm);
    }
};

pub fn alt(value: *Value, vm: *Vm) std.fmt.Alt(Alt, Alt.format) {
    return .{ .data = .{ .vm = vm, .value = value } };
}

pub fn count(value: *Value) usize {
    return switch (value.as) {
        .list => |v| v.len,
        .boolean => 1,
        .boolean_list => |v| v.len,
        .long => 1,
        .long_list => |v| v.len,
        .float => 1,
        .float_list => |v| v.len,
        .char => 1,
        .char_list => |v| v.len,
        .symbol => 1,
        .symbol_list => |v| v.len,
        .dict => |v| v.keys.count(),
        .lambda => 1,
        .unary_primitive => 1,
        .operator => 1,
        .projection => 1,
    };
}

pub const Type = enum(i8) {
    list = 0,
    boolean = -1,
    boolean_list = 1,
    // guid = -2,
    // guid_list = 2,
    // byte = -4,
    // byte_list = 4,
    // short = -5,
    // short_list = 5,
    // int = -6,
    // int_list = 6,
    long = -7,
    long_list = 7,
    // real = -8,
    // real_list = 8,
    float = -9,
    float_list = 9,
    char = -10,
    char_list = 10,
    symbol = -11,
    symbol_list = 11,
    // timestamp = -12,
    // timestamp_list = 12,
    // month = -13,
    // month_list = 13,
    // date = -14,
    // date_list = 14,
    // datetime = -15,
    // datetime_list = 15,
    // timespan = -16,
    // timespan_list = 16,
    // minute = -17,
    // minute_list = 17,
    // second = -18,
    // second_list = 18,
    // time = -19,
    // time_list = 19,
    // table = 98,
    dict = 99,
    lambda = 100,
    unary_primitive = 101,
    operator = 102,
    // iterator = 103,
    projection = 104,
    // composition = 105,
};

pub const Union = union(Type) {
    list: []*Value,
    boolean: bool,
    boolean_list: []bool,
    long: i64,
    long_list: []i64,
    float: f64,
    float_list: []f64,
    char: u8,
    char_list: []u8,
    symbol: Symbol,
    symbol_list: []Symbol,
    dict: Dictionary,
    lambda: Lambda,
    unary_primitive: UnaryPrimitive,
    operator: Operator,
    projection: Projection,
};

pub const Long = enum(i64) {
    null = std.math.minInt(i64),
    neg_inf = -std.math.maxInt(i64),
    inf = std.math.maxInt(i64),
    _,

    pub fn parse(buf: []const u8) !Long {
        switch (buf.len) {
            2 => if (buf[0] == '0') switch (std.ascii.toLower(buf[1])) {
                'n' => return .null,
                'w' => return .inf,
                else => {},
            },
            3 => if (buf[0] == '-' and buf[1] == '0' and std.ascii.toLower(buf[2]) == 'w') return .neg_inf,
            else => {},
        }
        return @enumFromInt(try std.fmt.parseInt(i64, buf, 10));
    }

    pub fn format(long: Long, w: *Io.Writer) !void {
        switch (long) {
            .null => try w.writeAll("0N"),
            .neg_inf => try w.writeAll("-0W"),
            .inf => try w.writeAll("0W"),
            else => try w.print("{d}", .{@intFromEnum(long)}),
        }
    }
};

pub const Symbol = enum(u32) {
    empty = 0,
    _,
};

pub const Dictionary = struct {
    keys: *Value,
    values: *Value,
};

pub const Lambda = struct {
    bytecode: []const u8,
    params: []const Symbol,
    locals: []const Symbol,
    globals: []const Symbol,
    constants: []*Value,
    source: []const u8,
};

pub const UnaryPrimitive = enum {
    identity, // ::
    flip, // +:
    neg, // -:
    first, // *:
    reciprocal, // %:
    where, // &:
    reverse, // |:
    null, // ^:
    group, // =:
    asc, // <:
    desc, // >:
    string, // $:
    list, // ,:
    count, // #:
    lower, // _:
    not, // ~:
    key, // !:
    distinct, // ?:
    type, // @:
    value, // .:
    read_text, // 0::
    read_binary, // 1::

    empty,

    pub fn format(self: UnaryPrimitive, w: *Io.Writer) !void {
        switch (self) {
            .identity, .empty => try w.writeAll("::"),
            .flip => try w.writeAll("+:"),
            .neg => try w.writeAll("-:"),
            .first => try w.writeAll("*:"),
            .reciprocal => try w.writeAll("%:"),
            .where => try w.writeAll("&:"),
            .reverse => try w.writeAll("|:"),
            .null => try w.writeAll("^:"),
            .group => try w.writeAll("=:"),
            .asc => try w.writeAll("<:"),
            .desc => try w.writeAll(">:"),
            .string => try w.writeAll("$:"),
            .list => try w.writeAll(",:"),
            .count => try w.writeAll("#:"),
            .lower => try w.writeAll("_:"),
            .not => try w.writeAll("~:"),
            .key => try w.writeAll("!:"),
            .distinct => try w.writeAll("?:"),
            .type => try w.writeAll("@:"),
            .value => try w.writeAll(".:"),
            .read_text => try w.writeAll("0::"),
            .read_binary => try w.writeAll("1::"),
        }
    }
};

pub const Operator = enum {
    assign, // :
    add, // +
    subtract, // -
    multiply, // *
    divide, // %
    @"and", // &
    @"or", // |
    fill, // ^
    equals, // =
    less_than, // <
    greater_than, // >
    cast, // $
    join, // ,
    take, // #
    drop, // _
    match, // ~
    dict, // !
    find, // ?
    apply_at, // @
    apply, // .
    file_text, // 0:
    file_binary, // 1:
    dynamic_load, // 2:

    pub fn format(self: Operator, w: *Io.Writer) !void {
        switch (self) {
            .assign => try w.writeByte(':'),
            .add => try w.writeByte('+'),
            .subtract => try w.writeByte('-'),
            .multiply => try w.writeByte('*'),
            .divide => try w.writeByte('%'),
            .@"and" => try w.writeByte('&'),
            .@"or" => try w.writeByte('|'),
            .fill => try w.writeByte('^'),
            .equals => try w.writeByte('='),
            .less_than => try w.writeByte('<'),
            .greater_than => try w.writeByte('>'),
            .cast => try w.writeByte('$'),
            .join => try w.writeByte(','),
            .take => try w.writeByte('#'),
            .drop => try w.writeByte('_'),
            .match => try w.writeByte('~'),
            .dict => try w.writeByte('!'),
            .find => try w.writeByte('?'),
            .apply_at => try w.writeByte('@'),
            .apply => try w.writeByte('.'),
            .file_text => try w.writeAll("0:"),
            .file_binary => try w.writeAll("1:"),
            .dynamic_load => try w.writeAll("2:"),
        }
    }
};

pub const Projection = struct {
    callee: *Value,
    args: []const *Value,
};

test {
    std.testing.refAllDecls(@This());
}
