const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zk = @import("../root.zig");
const Vm = zk.Vm;
const Value = zk.Value;

pub fn assign(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    @panic("NYI");
}

pub fn add(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.long, x_val + y_val),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, @as(f64, @floatFromInt(x_val)) + y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.float, x_val + @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, x_val + y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .dict => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn subtract(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.long, x_val - y_val),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, @as(f64, @floatFromInt(x_val)) - y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.float, x_val - @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, x_val - y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .dict => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn multiply(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.long, x_val * y_val),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, @as(f64, @floatFromInt(x_val)) * y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.float, x_val * @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, x_val * y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .dict => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn divide(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.float, @as(f64, @floatFromInt(x_val)) / @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, @as(f64, @floatFromInt(x_val)) / y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createValue(.float, x_val / @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createValue(.float, x_val / y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .dict => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .dict => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn @"and"(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn @"or"(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn fill(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn equals(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn less_than(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn greater_than(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn cast(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn join(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn take(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn drop(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn match(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn dict(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |val| switch (@as(Value.Long, @enumFromInt(val))) {
            .null => return vm.show(y),
            else => switch (val) {
                -3 => return vm.stringify(y),
                -5 => return vm.parse(y),
                -6 => return vm.eval(y),
                else => return error.nyi,
            },
        },
        .long_list => return error.nyi,
        .float => return error.nyi,
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .dict => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

pub fn find(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn apply_at(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn apply(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn file_text(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn file_binary(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

pub fn dynamic_load(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}
