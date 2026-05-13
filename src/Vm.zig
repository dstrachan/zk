const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zk = @import("root.zig");
const Ast = zk.Ast;
const Value = zk.Value;
const Symbol = Value.Symbol;
const UnaryPrimitive = Value.UnaryPrimitive;
const Operator = Value.Operator;

const Vm = @This();

pub const Error = Allocator.Error || std.fmt.ParseIntError || std.zig.ErrorBundle.RenderToStderrError ||
    Io.Writer.Error || error{ parse, rank, nyi, type, domain };

io: Io,
gpa: Allocator,
tree: *const Ast = undefined,
apply_unary: bool = false,
string_bytes: std.ArrayList(u8) = .empty,
string_table: std.HashMapUnmanaged(
    u32,
    void,
    std.hash_map.StringIndexContext,
    std.hash_map.default_max_load_percentage,
) = .empty,
stack: [1024]*Value = undefined,
stack_top: usize = 0,
unary_primitives: [std.meta.fields(UnaryPrimitive).len]*Value = undefined,
operators: [std.meta.fields(Operator).len]*Value = undefined,

pub fn init(io: Io, gpa: Allocator) !*Vm {
    const vm = try gpa.create(Vm);
    errdefer vm.deinit();
    vm.* = .{
        .io = io,
        .gpa = gpa,
    };

    var unary_primitives_created: usize = 0;
    errdefer for (0..unary_primitives_created) |i| vm.unary_primitives[i].deref(vm.gpa);
    inline for (&vm.unary_primitives, 0..) |*unary_primitive, i| {
        unary_primitive.* = try vm.createUnaryPrimitive(@enumFromInt(i));
        unary_primitives_created += 1;
    }

    var operators_created: usize = 0;
    errdefer for (0..operators_created) |i| vm.operators[i].deref(vm.gpa);
    inline for (&vm.operators, 0..) |*operator, i| {
        operator.* = try vm.createOperator(@enumFromInt(i));
        operators_created += 1;
    }

    assert(.empty == try vm.intern(""));

    return vm;
}

pub fn deinit(vm: *Vm) void {
    vm.string_table.deinit(vm.gpa);
    vm.string_bytes.deinit(vm.gpa);
    for (vm.unary_primitives) |v| v.deref(vm.gpa);
    for (vm.operators) |v| v.deref(vm.gpa);
    vm.gpa.destroy(vm);
}

pub fn compile(vm: *Vm, tree: *const Ast) !*Value {
    vm.tree = tree;
    return vm.compileNode(.root);
}

pub fn evalTree(vm: *Vm, tree: *const Ast) !*Value {
    const val = try vm.compile(tree);
    defer val.deref(vm.gpa);
    return vm.eval(val);
}

fn push(vm: *Vm, val: *Value) void {
    vm.stack[vm.stack_top] = val;
    vm.stack_top += 1;
}

fn applyImpl(vm: *Vm, func: *Value, args: []*Value) !*Value {
    assert(args.len > 0);
    std.log.debug("f = {f}", .{func.alt(vm)});
    for (args) |a| std.log.debug("arg = {f}", .{a.alt(vm)});

    switch (func.as) {
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
        .unary_primitive => |unary_primitive| {
            if (unary_primitive == .list and args.len > 1) {
                const first_type = @intFromEnum(args[0].as);
                const is_vector = for (args[1..]) |a| {
                    if (first_type != @intFromEnum(a.as)) break false;
                } else true;
                if (is_vector) {
                    switch (args[0].as) {
                        .list => {},
                        .boolean => {
                            const val = try vm.createBooleanList(args.len);
                            errdefer comptime unreachable;
                            for (val.as.boolean_list, args) |*v, a| v.* = a.as.boolean;
                            return val;
                        },
                        .boolean_list => {},
                        .long => {
                            const val = try vm.createLongList(args.len);
                            errdefer comptime unreachable;
                            for (val.as.long_list, args) |*v, a| v.* = a.as.long;
                            return val;
                        },
                        .long_list => {},
                        .float => {
                            const val = try vm.createFloatList(args.len);
                            errdefer comptime unreachable;
                            for (val.as.float_list, args) |*v, a| v.* = a.as.float;
                            return val;
                        },
                        .float_list => {},
                        .char => {
                            const val = try vm.createCharList(args.len);
                            errdefer comptime unreachable;
                            for (val.as.char_list, args) |*v, a| v.* = a.as.char;
                            return val;
                        },
                        .char_list => {},
                        .symbol => {
                            const val = try vm.createSymbolList(args.len);
                            errdefer comptime unreachable;
                            for (val.as.symbol_list, args) |*v, a| v.* = a.as.symbol;
                            return val;
                        },
                        .symbol_list => {},
                        .unary_primitive => {},
                        .operator => {},
                    }
                }

                const val = try vm.createList(args.len);
                errdefer comptime unreachable;
                for (val.as.list, args) |*v, a| v.* = a.ref();
                return val;
            }

            if (args.len > 1) return error.rank;
            return vm.applyUnaryPrimitive(unary_primitive, args[0]);
        },
        .operator => |operator| {
            if (args.len > 2) return error.rank;
            if (args.len == 1) return error.nyi;
            return vm.applyOperator(operator, args[0], args[1]);
        },
    }

    return vm.createFloat(0);
}

//
// Unary primitives
//

fn applyUnaryPrimitive(vm: *Vm, unary_primitive: UnaryPrimitive, x: *Value) !*Value {
    switch (unary_primitive) {
        .identity => return vm.identity(x),
        .flip => return vm.flip(x),
        .neg => return vm.neg(x),
        .first => return vm.first(x),
        .reciprocal => return vm.reciprocal(x),
        .where => return vm.where(x),
        .reverse => return vm.reverse(x),
        .null => return vm.null(x),
        .group => return vm.group(x),
        .asc => return vm.asc(x),
        .desc => return vm.desc(x),
        .string => return vm.string(x),
        .list => return vm.list(x),
        .count => return vm.count(x),
        .lower => return vm.lower(x),
        .not => return vm.not(x),
        .key => return vm.key(x),
        .distinct => return vm.distinct(x),
        .type => return vm.type(x),
        .value => return vm.value(x),
        .read_text => return vm.readText(x),
        .read_binary => return vm.readBinary(x),
    }
}

fn identity(_: *Vm, x: *Value) !*Value {
    return x.ref();
}

fn flip(vm: *Vm, x: *Value) !*Value {
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

fn neg(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => |val| {
            const v = try vm.createList(val.len);
            var i: usize = 0;
            errdefer {
                for (v.as.list[0..i]) |elem| elem.deref(vm.gpa);
                vm.gpa.destroy(v);
            }
            for (v.as.list, val) |*vv, elem| {
                vv.* = try vm.neg(elem);
                i += 1;
            }
            return v;
        },
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |val| return vm.createLong(-val),
        .long_list => |val| {
            const v = try vm.createLongList(val.len);
            errdefer v.deref(vm.gpa);
            for (v.as.long_list, val) |*vv, elem| vv.* = -elem;
            return v;
        },
        .float => |val| return vm.createFloat(-val),
        .float_list => |val| {
            const v = try vm.createFloatList(val.len);
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

fn first(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => |val| return val[0].ref(),
        .boolean => return x.ref(),
        .boolean_list => |val| return vm.createBoolean(val[0]),
        .long => return x.ref(),
        .long_list => |val| return vm.createLong(val[0]),
        .float => return x.ref(),
        .float_list => |val| return vm.createFloat(val[0]),
        .char => return x.ref(),
        .char_list => |val| return vm.createChar(val[0]),
        .symbol => return x.ref(),
        .symbol_list => |val| return vm.createSymbol(val[0]),
        .unary_primitive => return x.ref(),
        .operator => return x.ref(),
    }
}

fn reciprocal(vm: *Vm, x: *Value) !*Value {
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

fn where(vm: *Vm, x: *Value) !*Value {
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

fn reverse(vm: *Vm, x: *Value) !*Value {
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

fn @"null"(vm: *Vm, x: *Value) !*Value {
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

fn group(vm: *Vm, x: *Value) !*Value {
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

fn asc(vm: *Vm, x: *Value) !*Value {
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

fn desc(vm: *Vm, x: *Value) !*Value {
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

fn string(vm: *Vm, x: *Value) !*Value {
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

fn list(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .boolean => |val| {
            const v = try vm.createBooleanList(1);
            errdefer comptime unreachable;
            v.as.boolean_list[0] = val;
            return v;
        },
        .boolean_list => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .long => |val| {
            const v = try vm.createLongList(1);
            errdefer comptime unreachable;
            v.as.long_list[0] = val;
            return v;
        },
        .long_list => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .float => |val| {
            const v = try vm.createFloatList(1);
            errdefer comptime unreachable;
            v.as.float_list[0] = val;
            return v;
        },
        .float_list => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .char => |val| {
            const v = try vm.createCharList(1);
            errdefer comptime unreachable;
            v.as.char_list[0] = val;
            return v;
        },
        .char_list => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .symbol => |val| {
            const v = try vm.createSymbolList(1);
            errdefer comptime unreachable;
            v.as.symbol_list[0] = val;
            return v;
        },
        .symbol_list => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .unary_primitive => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
        .operator => {
            const v = try vm.createList(1);
            errdefer comptime unreachable;
            v.as.list[0] = x.ref();
            return v;
        },
    }
}

fn count(vm: *Vm, x: *Value) !*Value {
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

fn lower(vm: *Vm, x: *Value) !*Value {
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

fn not(vm: *Vm, x: *Value) !*Value {
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

fn key(vm: *Vm, x: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |val| {
            if (val < 0) return error.domain;
            const long_list = try vm.createLongList(@intCast(val));
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

fn distinct(vm: *Vm, x: *Value) !*Value {
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

fn @"type"(vm: *Vm, x: *Value) !*Value {
    return vm.createLong(@intFromEnum(x.as));
}

fn value(vm: *Vm, x: *Value) !*Value {
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

fn readText(vm: *Vm, x: *Value) !*Value {
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

fn readBinary(vm: *Vm, x: *Value) !*Value {
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

//
// Operators
//

fn applyOperator(vm: *Vm, operator: Operator, x: *Value, y: *Value) !*Value {
    switch (operator) {
        .assign => unreachable,
        .add => return vm.add(x, y),
        .subtract => return vm.subtract(x, y),
        .multiply => return vm.multiply(x, y),
        .divide => return vm.divide(x, y),
        .@"and" => return vm.@"and"(x, y),
        .@"or" => return vm.@"or"(x, y),
        .fill => return vm.fill(x, y),
        .equals => return vm.equals(x, y),
        .less_than => return vm.lessThan(x, y),
        .greater_than => return vm.greaterThan(x, y),
        .cast => return vm.cast(x, y),
        .join => return vm.join(x, y),
        .take => return vm.take(x, y),
        .drop => return vm.drop(x, y),
        .match => return vm.match(x, y),
        .dict => return vm.dict(x, y),
        .find => return vm.find(x, y),
        .apply_at => return vm.applyAt(x, y),
        .apply => return vm.apply(x, y),
        .file_text => return vm.fileText(x, y),
        .file_binary => return vm.fileBinary(x, y),
        .dynamic_load => return vm.dynamicLoad(x, y),
    }
}

fn add(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createLong(x_val + y_val),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(@as(f64, @floatFromInt(x_val)) + y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createFloat(x_val + @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(x_val + y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

fn subtract(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createLong(x_val - y_val),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(@as(f64, @floatFromInt(x_val)) - y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createFloat(x_val - @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(x_val - y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

fn multiply(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createLong(x_val * y_val),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(@as(f64, @floatFromInt(x_val)) * y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createFloat(x_val * @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(x_val * y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

fn divide(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createFloat(@as(f64, @floatFromInt(x_val)) / @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(@as(f64, @floatFromInt(x_val)) / y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .long_list => return error.nyi,
        .float => |x_val| switch (y.as) {
            .list => return error.nyi,
            .boolean => return error.nyi,
            .boolean_list => return error.nyi,
            .long => |y_val| return vm.createFloat(x_val / @as(f64, @floatFromInt(y_val))),
            .long_list => return error.nyi,
            .float => |y_val| return vm.createFloat(x_val / y_val),
            .float_list => return error.nyi,
            .char => return error.nyi,
            .char_list => return error.nyi,
            .symbol => return error.nyi,
            .symbol_list => return error.nyi,
            .unary_primitive => return error.nyi,
            .operator => return error.nyi,
        },
        .float_list => return error.nyi,
        .char => return error.nyi,
        .char_list => return error.nyi,
        .symbol => return error.nyi,
        .symbol_list => return error.nyi,
        .unary_primitive => return error.nyi,
        .operator => return error.nyi,
    }
}

fn @"and"(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn @"or"(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn fill(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn equals(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn lessThan(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn greaterThan(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn cast(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn join(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn take(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn drop(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn match(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn dict(vm: *Vm, x: *Value, y: *Value) !*Value {
    switch (x.as) {
        .list => return error.nyi,
        .boolean => return error.nyi,
        .boolean_list => return error.nyi,
        .long => |val| switch (val) {
            -5 => return vm.parse(y),
            -6 => return vm.eval(y),
            else => return error.nyi,
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

fn find(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn applyAt(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn apply(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn fileText(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn fileBinary(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

fn dynamicLoad(vm: *Vm, x: *Value, y: *Value) !*Value {
    _ = vm; // autofix
    _ = x; // autofix
    _ = y; // autofix
    unreachable;
}

//
// Internal functions
//

fn parse(vm: *Vm, x: *Value) !*Value {
    assert(x.as == .char_list);

    const slice = try vm.gpa.dupeSentinel(u8, x.as.char_list, 0);
    defer vm.gpa.free(slice);

    var tree: Ast = try .parse(vm.gpa, slice);
    defer tree.deinit(vm.gpa);
    if (tree.errors.len > 0) {
        try zk.printAstErrorsToStderr(vm.gpa, vm.io, tree, "<parse>", .auto);
        return error.parse;
    }

    return vm.compile(&tree);
}

fn eval(vm: *Vm, x: *Value) Error!*Value {
    switch (x.as) {
        .list => |val| {
            if (val.len == 1 and val[0].as == .symbol_list) return val[0].ref();

            var it = std.mem.reverseIterator(val);
            while (it.next()) |entry| vm.push(try vm.eval(entry));

            const stack = vm.stack[vm.stack_top - val.len .. vm.stack_top];
            // TODO: Remove reverse
            std.mem.reverse(*Value, stack);
            defer {
                vm.stack_top -= val.len;
                for (stack) |v| v.deref(vm.gpa);
            }

            const func = stack[0];
            const args = stack[1..];

            return vm.applyImpl(func, args);
        },
        .symbol => @panic("NYI"),
        .symbol_list => |val| {
            assert(val.len == 1);
            return vm.createSymbol(val[0]);
        },
        else => return x.ref(),
    }
}

fn compileNode(vm: *Vm, node: Ast.Node.Index) !*Value {
    const tree = vm.tree;
    const gpa = vm.gpa;

    switch (tree.nodeTag(node)) {
        .root => {
            const nodes = tree.extraDataSlice(tree.nodeData(.root).extra_range, Ast.Node.Index);
            assert(nodes.len == 1);
            return vm.compileNode(nodes[0]);
        },
        .empty => @panic("NYI"),

        .grouped_expression => return vm.compileNode(tree.nodeData(node).node_and_token[0]),
        .empty_list => return vm.createList(0),
        .list => {
            const nodes = tree.extraDataSlice(tree.nodeData(node).extra_range, Ast.Node.Index);

            const val = try vm.createList(nodes.len + 1);
            var i: usize = 0;
            errdefer {
                for (val.as.list[0..i]) |v| v.deref(gpa);
                gpa.destroy(val);
            }

            val.as.list[0] = vm.unary_primitives[@intFromEnum(UnaryPrimitive.list)].ref();
            i += 1;

            for (nodes) |n| {
                val.as.list[i] = try vm.compileNode(n);
                i += 1;
            }

            return val;
        },
        .table_literal => @panic("NYI"),

        .lambda => @panic("NYI"),

        .expr_block => @panic("NYI"),

        .call => {
            const nodes = tree.extraDataSlice(tree.nodeData(node).extra_range, Ast.Node.Index);

            const val = try vm.createList(nodes.len);
            var i: usize = 0;
            errdefer {
                for (val.as.list[0..i]) |v| v.deref(gpa);
                gpa.destroy(val);
            }

            for (nodes) |n| {
                val.as.list[i] = try vm.compileNode(n);
                i += 1;
            }

            return val;
        },
        .apply_unary => {
            const lhs, const rhs = tree.nodeData(node).node_and_node;

            const rhs_value = try vm.compileNode(rhs);
            errdefer rhs_value.deref(gpa);

            const lhs_value = value: {
                const prev_force_unary = vm.apply_unary;
                defer vm.apply_unary = prev_force_unary;
                vm.apply_unary = true;
                break :value try vm.compileNode(lhs);
            };
            errdefer lhs_value.deref(gpa);

            const val = try vm.createList(2);
            errdefer comptime unreachable;

            val.as.list[0] = lhs_value;
            val.as.list[1] = rhs_value;

            return val;
        },
        .apply_binary => {
            const lhs, const maybe_rhs = tree.nodeData(node).node_and_opt_node;
            const op: Ast.Node.Index = @enumFromInt(tree.nodeMainToken(node));
            if (maybe_rhs.unwrap()) |rhs| {
                const rhs_value = try vm.compileNode(rhs);
                errdefer rhs_value.deref(gpa);

                const op_value = try vm.compileNode(op);
                errdefer op_value.deref(gpa);

                const lhs_value = try vm.compileNode(lhs);
                errdefer lhs_value.deref(gpa);

                const val = try vm.createList(3);
                errdefer comptime unreachable;

                val.as.list[0] = op_value;
                val.as.list[1] = lhs_value;
                val.as.list[2] = rhs_value;

                return val;
            } else unreachable;
        },

        .bang => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.key)].ref() else vm.operators[@intFromEnum(Operator.dict)].ref(),
        .hash => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.count)].ref() else vm.operators[@intFromEnum(Operator.take)].ref(),
        .dollar => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.string)].ref() else vm.operators[@intFromEnum(Operator.cast)].ref(),
        .percent => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.reciprocal)].ref() else vm.operators[@intFromEnum(Operator.divide)].ref(),
        .ampersand => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.where)].ref() else vm.operators[@intFromEnum(Operator.@"and")].ref(),
        .asterisk => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.first)].ref() else vm.operators[@intFromEnum(Operator.multiply)].ref(),
        .plus => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.flip)].ref() else vm.operators[@intFromEnum(Operator.add)].ref(),
        .comma => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.list)].ref() else vm.operators[@intFromEnum(Operator.join)].ref(),
        .minus => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.neg)].ref() else vm.operators[@intFromEnum(Operator.subtract)].ref(),
        .dot => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.value)].ref() else vm.operators[@intFromEnum(Operator.apply)].ref(),
        .colon => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.identity)].ref() else vm.operators[@intFromEnum(Operator.assign)].ref(),
        .angle_bracket_left => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.asc)].ref() else vm.operators[@intFromEnum(Operator.less_than)].ref(),
        .equals => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.group)].ref() else vm.operators[@intFromEnum(Operator.equals)].ref(),
        .angle_bracket_right => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.desc)].ref() else vm.operators[@intFromEnum(Operator.greater_than)].ref(),
        .question_mark => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.distinct)].ref() else vm.operators[@intFromEnum(Operator.find)].ref(),
        .at => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.type)].ref() else vm.operators[@intFromEnum(Operator.apply_at)].ref(),
        .caret => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.null)].ref() else vm.operators[@intFromEnum(Operator.fill)].ref(),
        .underscore => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.lower)].ref() else vm.operators[@intFromEnum(Operator.drop)].ref(),
        .pipe => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.reverse)].ref() else vm.operators[@intFromEnum(Operator.@"or")].ref(),
        .tilde => return if (vm.apply_unary) vm.unary_primitives[@intFromEnum(UnaryPrimitive.not)].ref() else vm.operators[@intFromEnum(Operator.match)].ref(),

        .bang_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.key)].ref(),
        .hash_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.count)].ref(),
        .dollar_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.string)].ref(),
        .percent_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.reciprocal)].ref(),
        .ampersand_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.where)].ref(),
        .asterisk_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.first)].ref(),
        .plus_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.flip)].ref(),
        .comma_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.list)].ref(),
        .minus_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.neg)].ref(),
        .dot_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.value)].ref(),
        .colon_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.identity)].ref(),
        .angle_bracket_left_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.asc)].ref(),
        .equals_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.group)].ref(),
        .angle_bracket_right_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.desc)].ref(),
        .question_mark_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.distinct)].ref(),
        .at_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.type)].ref(),
        .caret_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.null)].ref(),
        .underscore_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.lower)].ref(),
        .pipe_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.reverse)].ref(),
        .tilde_colon => return vm.unary_primitives[@intFromEnum(UnaryPrimitive.not)].ref(),

        .apostrophe => @panic("NYI"),
        .apostrophe_colon => @panic("NYI"),
        .slash => @panic("NYI"),
        .slash_colon => @panic("NYI"),
        .backslash => @panic("NYI"),
        .backslash_colon => @panic("NYI"),

        .number_literal => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);
            const long = std.fmt.parseInt(i64, slice, 10) catch {
                const float = try std.fmt.parseFloat(f64, slice);
                return vm.createFloat(float);
            };
            return vm.createLong(long);
        },
        .number_list_literal => {
            const first_token = tree.nodeMainToken(node);
            const last_token = tree.nodeData(node).token;
            const long_list = try vm.createLongList(last_token - first_token + 1);
            errdefer long_list.deref(gpa);
            for (first_token..last_token + 1, 0..) |tok, i| {
                const slice = tree.tokenSlice(@intCast(tok));
                const long = try std.fmt.parseInt(i64, slice, 10);
                long_list.as.long_list[i] = long;
            }
            return long_list;
        },
        .string_literal => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);

            const buffer = try vm.gpa.alloc(u8, slice.len - 2);
            defer vm.gpa.free(buffer);

            var fixed: Io.Writer = .fixed(buffer);
            const writer = &fixed;

            var index: usize = 1;
            while (true) {
                const b = slice[index];
                switch (b) {
                    '\\' => {
                        switch (slice[index + 1]) {
                            't' => try writer.writeByte('\t'),
                            'n' => try writer.writeByte('\n'),
                            'r' => try writer.writeByte('\r'),
                            '"' => try writer.writeByte('"'),
                            '\\' => try writer.writeByte('\\'),
                            else => unreachable,
                        }
                        index += 2;
                    },
                    '"' => break,
                    else => {
                        try writer.writeByte(b);
                        index += 1;
                    },
                }
            }

            const buffered = fixed.buffered();
            if (buffered.len == 1) return vm.createChar(buffered[0]);
            const char_list = try vm.createCharList(buffered.len);
            errdefer comptime unreachable;
            @memcpy(char_list.as.char_list, buffered);
            return char_list;
        },
        .multiline_string_literal => @panic("NYI"),
        .symbol_literal => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);
            const symbol = try vm.intern(slice[1..]);
            const symbol_list = try vm.createSymbolList(1);
            errdefer comptime unreachable;
            symbol_list.as.symbol_list[0] = symbol;
            return symbol_list;
        },
        .symbol_list_literal => {
            const first_token = tree.nodeMainToken(node);
            const last_token = tree.nodeData(node).token;
            const symbol_list = try vm.createSymbolList(last_token - first_token + 1);
            errdefer symbol_list.deref(gpa);
            for (first_token..last_token + 1, 0..) |tok, i| {
                const slice = tree.tokenSlice(@intCast(tok));
                const symbol = try vm.intern(slice[1..]);
                symbol_list.as.symbol_list[i] = symbol;
            }
            const val = try vm.createList(1);
            errdefer comptime unreachable;
            val.as.list[0] = symbol_list;
            return val;
        },
        .identifier => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);
            const symbol = try vm.intern(slice);
            return vm.createSymbol(symbol);
        },
    }
}

fn intern(vm: *Vm, bytes: []const u8) !Symbol {
    const str_index: u32 = @intCast(vm.string_bytes.items.len);
    try vm.string_bytes.appendSlice(vm.gpa, bytes);
    const gop = try vm.string_table.getOrPutContextAdapted(
        vm.gpa,
        vm.string_bytes.items[str_index..],
        std.hash_map.StringIndexAdapter{ .bytes = &vm.string_bytes },
        std.hash_map.StringIndexContext{ .bytes = &vm.string_bytes },
    );
    if (gop.found_existing) {
        vm.string_bytes.shrinkRetainingCapacity(str_index);
        return @enumFromInt(gop.key_ptr.*);
    } else {
        gop.key_ptr.* = str_index;
        try vm.string_bytes.append(vm.gpa, 0);
        return @enumFromInt(str_index);
    }
}

pub fn internedString(vm: *Vm, index: Symbol) [:0]const u8 {
    const slice = vm.string_bytes.items[@intFromEnum(index)..];
    return slice[0..std.mem.findScalar(u8, slice, 0).? :0];
}

fn createList(vm: *Vm, len: usize) !*Value {
    return vm.allocValue(.list, len);
}

fn createBoolean(vm: *Vm, val: bool) !*Value {
    return vm.createValue(.boolean, val);
}

fn createBooleanList(vm: *Vm, len: usize) !*Value {
    return vm.allocValue(.boolean_list, len);
}

fn createLong(vm: *Vm, val: i64) !*Value {
    return vm.createValue(.long, val);
}

fn createLongList(vm: *Vm, len: usize) !*Value {
    return vm.allocValue(.long_list, len);
}

fn createFloat(vm: *Vm, val: f64) !*Value {
    return vm.createValue(.float, val);
}

fn createFloatList(vm: *Vm, len: usize) !*Value {
    return vm.allocValue(.float_list, len);
}

fn createChar(vm: *Vm, val: u8) !*Value {
    return vm.createValue(.char, val);
}

fn createCharList(vm: *Vm, len: usize) !*Value {
    return vm.allocValue(.char_list, len);
}

fn createSymbol(vm: *Vm, val: Symbol) !*Value {
    return vm.createValue(.symbol, val);
}

fn createSymbolList(vm: *Vm, len: usize) !*Value {
    return vm.allocValue(.symbol_list, len);
}

fn createUnaryPrimitive(vm: *Vm, val: UnaryPrimitive) !*Value {
    return vm.createValue(.unary_primitive, val);
}

fn createOperator(vm: *Vm, val: Operator) !*Value {
    return vm.createValue(.operator, val);
}

fn createValue(vm: *Vm, comptime tag: Value.Type, val: @FieldType(Value.Union, @tagName(tag))) !*Value {
    const self = try vm.gpa.create(Value);
    errdefer comptime unreachable;
    self.* = .{ .as = @unionInit(Value.Union, @tagName(tag), val) };
    return self;
}

fn allocValue(vm: *Vm, comptime tag: Value.Type, len: usize) !*Value {
    const T = @typeInfo(@FieldType(Value.Union, @tagName(tag))).pointer.child;
    const val = try vm.gpa.alloc(T, len);
    errdefer vm.gpa.free(val);
    return vm.createValue(tag, val);
}

test {
    std.testing.refAllDecls(@This());
}

test {
    const gpa = std.testing.allocator;
    const source =
        \\-6!-5!"-6!-5!\"3*4+5\""
    ;
    var vm: *Vm = try .init(std.testing.io, gpa);
    defer vm.deinit();

    var tree: Ast = try .parse(gpa, source);
    defer tree.deinit(gpa);

    const val = try vm.evalTree(&tree);
    defer val.deref(gpa);

    try std.testing.expectEqual(27, val.as.long);
}
