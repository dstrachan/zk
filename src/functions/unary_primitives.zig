const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zk = @import("../root.zig");
const Vm = zk.Vm;
const Value = zk.Value;

pub fn identity(_: *Vm, x: *Value) !*Value {
    return x.ref();
}

pub fn flip(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn neg(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => |val| {
            const v = try vm.allocValue(.list, val.len);
            var i: usize = 0;
            errdefer {
                for (v.as.list[0..i]) |elem| elem.deref(vm.gpa);
                vm.gpa.destroy(v);
            }
            for (v.as.list, val) |*vv, elem| {
                vv.* = try neg(vm, elem);
                i += 1;
            }
            return v;
        },
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |val| return vm.createValue(.long, -val),
        .long_list => |val| {
            const v = try vm.allocValue(.long_list, val.len);
            errdefer v.deref(vm.gpa);
            for (v.as.long_list, val) |*vv, elem| vv.* = -elem;
            return v;
        },
        .float => |val| return vm.createValue(.float, -val),
        .float_list => |val| {
            const v = try vm.allocValue(.float_list, val.len);
            errdefer v.deref(vm.gpa);
            for (v.as.float_list, val) |*vv, elem| vv.* = -elem;
            return v;
        },
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.type,
        .symbol_list => return error.type,
        .unary_primitive => return error.type,
        .operator => return error.type,
    }
}

pub fn first(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => |val| return val[0].ref(),
        .boolean => return x.ref(),
        .boolean_list => |val| return vm.createValue(.boolean, val[0]),
        .long => return x.ref(),
        .long_list => |val| return vm.createValue(.long, val[0]),
        .float => return x.ref(),
        .float_list => |val| return vm.createValue(.float, val[0]),
        .char => return x.ref(),
        .char_list => |val| return vm.createValue(.char, val[0]),
        .symbol => return x.ref(),
        .symbol_list => |val| return vm.createValue(.symbol, val[0]),
        .unary_primitive => return x.ref(),
        .operator => return x.ref(),
    }
}

pub fn reciprocal(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn where(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn reverse(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn @"null"(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn group(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn asc(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn desc(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn string(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn list(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .boolean => |val| {
            const v = try vm.allocValue(.boolean_list, 1);
            errdefer comptime unreachable;
            v.as.boolean_list[0] = val;
            return v;
        },
        .boolean_list => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .long => |val| {
            const v = try vm.allocValue(.long_list, 1);
            errdefer comptime unreachable;
            v.as.long_list[0] = val;
            return v;
        },
        .long_list => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .float => |val| {
            const v = try vm.allocValue(.float_list, 1);
            errdefer comptime unreachable;
            v.as.float_list[0] = val;
            return v;
        },
        .float_list => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .char => |val| {
            const v = try vm.allocValue(.char_list, 1);
            errdefer comptime unreachable;
            v.as.char_list[0] = val;
            return v;
        },
        .char_list => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .symbol => |val| {
            const v = try vm.allocValue(.symbol_list, 1);
            errdefer comptime unreachable;
            v.as.symbol_list[0] = val;
            return v;
        },
        .symbol_list => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .unary_primitive => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .operator => {
            const v = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
    }
}

pub fn count(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn lower(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn not(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn key(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |val| {
            if (val < 0) return error.domain;
            const long_list = try vm.allocValue(.long_list, @intCast(val));
            errdefer comptime unreachable;
            for (long_list.as.long_list, 0..) |*v, i| v.* = @intCast(i);
            return long_list;
        },
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn distinct(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn @"type"(vm: *Vm, x: *Value) !*Value {
    return vm.createValue(.long, @intFromEnum(x.as));
}

pub fn value(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn read_text(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn read_binary(vm: *Vm, x: *Value) !*Value {
    _ = vm; // autofix
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => return error.nyi,
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}
