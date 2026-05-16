const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zk = @import("root.zig");
const Ast = zk.Ast;
const Value = zk.Value;
const Long = Value.Long;
const Symbol = Value.Symbol;
const UnaryPrimitive = Value.UnaryPrimitive;
const Operator = Value.Operator;

const Vm = @This();

const ParseError = Allocator.Error || std.fmt.ParseFloatError || Io.Writer.Error;
pub const Error = ParseError || std.zig.ErrorBundle.RenderToStderrError ||
    error{ rank, type, parse, nyi, domain, identifier };

io: Io,
gpa: Allocator,
stdout: *Io.Writer,
tree: *const Ast = undefined,
string_bytes: std.ArrayList(u8) = .empty,
string_table: std.HashMapUnmanaged(
    u32,
    void,
    std.hash_map.StringIndexContext,
    std.hash_map.default_max_load_percentage,
) = .empty,
stack: std.ArrayList(*Value) = .empty,
constants: [std.meta.fields(Constant).len]*Value = undefined,
unary_primitives: [std.meta.fields(UnaryPrimitive).len]*Value = undefined,
operators: [std.meta.fields(Operator).len]*Value = undefined,
state: *Value = undefined,

const Constant = enum(u8) {
    empty_list,
    zero,
    one,
    semicolon,
    null_symbol,
};

pub fn init(io: Io, gpa: Allocator, stdout: *Io.Writer) !*Vm {
    const vm = try gpa.create(Vm);
    errdefer vm.deinit();
    vm.* = .{
        .io = io,
        .gpa = gpa,
        .stdout = stdout,
    };

    var constants_created: usize = 0;
    errdefer for (0..constants_created) |i| vm.constants[i].deref(vm.gpa);
    vm.constants[@intFromEnum(Constant.empty_list)] = try vm.allocValue(.list, 0);
    constants_created += 1;
    vm.constants[@intFromEnum(Constant.zero)] = try vm.createValue(.long, 0);
    constants_created += 1;
    vm.constants[@intFromEnum(Constant.one)] = try vm.createValue(.long, 1);
    constants_created += 1;
    vm.constants[@intFromEnum(Constant.semicolon)] = try vm.createValue(.char, ';');
    constants_created += 1;
    vm.constants[@intFromEnum(Constant.null_symbol)] = try vm.createValue(.symbol, try vm.intern(""));
    constants_created += 1;

    var unary_primitives_created: usize = 0;
    errdefer for (0..unary_primitives_created) |i| vm.unary_primitives[i].deref(vm.gpa);
    inline for (&vm.unary_primitives, 0..) |*unary_primitive, i| {
        unary_primitive.* = try vm.createValue(.unary_primitive, @enumFromInt(i));
        unary_primitives_created += 1;
    }

    var operators_created: usize = 0;
    errdefer for (0..operators_created) |i| vm.operators[i].deref(vm.gpa);
    inline for (&vm.operators, 0..) |*operator, i| {
        operator.* = try vm.createValue(.operator, @enumFromInt(i));
        operators_created += 1;
    }

    const keys = try vm.allocValue(.symbol_list, 1);
    errdefer keys.deref(gpa);
    keys.as.symbol_list[0] = .empty;

    const values = try vm.allocValue(.list, 1);
    errdefer values.deref(gpa);
    values.as.list[0] = vm.getUnaryPrimitive(.identity);

    const dict = try vm.createValue(.dict, .{ .keys = keys, .values = values });
    errdefer comptime unreachable;

    vm.state = dict;

    return vm;
}

pub fn deinit(vm: *Vm) void {
    vm.string_table.deinit(vm.gpa);
    vm.string_bytes.deinit(vm.gpa);
    vm.state.deref(vm.gpa);
    for (vm.constants) |v| v.deref(vm.gpa);
    for (vm.unary_primitives) |v| v.deref(vm.gpa);
    for (vm.operators) |v| v.deref(vm.gpa);
    assert(vm.stack.items.len == 0);
    vm.stack.deinit(vm.gpa);
    vm.gpa.destroy(vm);
}

fn getConstant(vm: *Vm, constant: Constant) *Value {
    return vm.constants[@intFromEnum(constant)].ref();
}

fn getUnaryPrimitive(vm: *Vm, unary_primitive: UnaryPrimitive) *Value {
    return vm.unary_primitives[@intFromEnum(unary_primitive)].ref();
}

fn getOperator(vm: *Vm, operator: Operator) *Value {
    return vm.operators[@intFromEnum(operator)].ref();
}

fn parseTree(vm: *Vm, tree: *const Ast) !*Value {
    vm.tree = tree;
    return vm.parseNode(.root);
}

pub fn evalTree(vm: *Vm, tree: *const Ast) !*Value {
    const value = try vm.parseTree(tree);
    defer value.deref(vm.gpa);
    return vm.eval(value);
}

fn push(vm: *Vm, value: *Value) void {
    vm.stack.append(vm.gpa, value) catch @panic("oom");
}

fn applyImpl(vm: *Vm, func: *Value, args: []*Value) !*Value {
    assert(args.len > 0);
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
        .dict => return error.nyi,
        .lambda => return error.nyi,
        .unary_primitive => |unary_primitive| {
            if (unary_primitive == .list and args.len > 1) return vm.enlist(args);
            if (args.len > 1) return error.rank;
            switch (unary_primitive) {
                .empty => unreachable, // TODO: This might not be unreachable.
                inline else => |t| return @field(zk.unary_primitives, @tagName(t))(vm, args[0]),
            }
            return vm.applyUnaryPrimitive(unary_primitive, args[0]);
        },
        .operator => |operator| {
            if (args.len > 2) return error.rank;
            if (args.len == 1) {
                var values: std.ArrayList(*Value) = try .initCapacity(vm.gpa, 1);
                defer values.deinit(vm.gpa);
                errdefer for (values.items) |v| v.deref(vm.gpa);

                values.appendAssumeCapacity(args[0].ref());

                const callee = func.ref();
                errdefer callee.deref(vm.gpa);

                return vm.createValue(.projection, .{
                    .callee = callee,
                    .args = values.toOwnedSliceAssert(),
                });
            }
            if ((args[0].as == .unary_primitive and args[0].as.unary_primitive == .empty) or
                (args[1].as == .unary_primitive and args[1].as.unary_primitive == .empty))
            {
                var values: std.ArrayList(*Value) = try .initCapacity(vm.gpa, 2);
                defer values.deinit(vm.gpa);
                errdefer for (values.items) |v| v.deref(vm.gpa);

                values.appendAssumeCapacity(args[0].ref());
                values.appendAssumeCapacity(args[1].ref());

                const callee = func.ref();
                errdefer callee.deref(vm.gpa);

                return vm.createValue(.projection, .{
                    .callee = callee,
                    .args = values.toOwnedSliceAssert(),
                });
            } else {
                switch (operator) {
                    inline else => |t| return @field(zk.operators, @tagName(t))(vm, args[0], args[1]),
                }
            }
        },
        .projection => |projection| {
            const rank = projection.callee.rank();
            const args_len = len: {
                var len: usize = projection.args.len;
                for (projection.args) |a| {
                    if (a.as == .unary_primitive and a.as.unary_primitive == .empty) len -= 1;
                }
                break :len len;
            } + args.len;
            if (args_len > rank) return error.rank;

            var new_args: std.ArrayList(*Value) = try .initCapacity(vm.gpa, args_len);
            defer new_args.deinit(vm.gpa);

            var j: usize = 0;
            for (0..args_len) |i| {
                if (i < projection.args.len) {
                    if (projection.args[i].as == .unary_primitive and projection.args[i].as.unary_primitive == .empty) {
                        new_args.appendAssumeCapacity(args[j]);
                        j += 1;
                    } else {
                        new_args.appendAssumeCapacity(projection.args[i]);
                    }
                } else {
                    new_args.appendAssumeCapacity(args[j]);
                    j += 1;
                }
            }

            return vm.applyImpl(projection.callee, new_args.items);
        },
    }
}

pub fn enlist(vm: *Vm, args: []*Value) !*Value {
    const first_type = @intFromEnum(args[0].as);
    const is_vector = for (args[1..]) |a| {
        if (first_type != @intFromEnum(a.as)) break false;
    } else true;
    if (is_vector) {
        switch (args[0].as) {
            .list => {},
            .boolean => {
                const value = try vm.allocValue(.boolean_list, args.len);
                errdefer comptime unreachable;
                for (value.as.boolean_list, args) |*v, a| v.* = a.as.boolean;
                return value;
            },
            .boolean_list => {},
            .long => {
                const value = try vm.allocValue(.long_list, args.len);
                errdefer comptime unreachable;
                for (value.as.long_list, args) |*v, a| v.* = a.as.long;
                return value;
            },
            .long_list => {},
            .float => {
                const value = try vm.allocValue(.float_list, args.len);
                errdefer comptime unreachable;
                for (value.as.float_list, args) |*v, a| v.* = a.as.float;
                return value;
            },
            .float_list => {},
            .char => {
                const value = try vm.allocValue(.char_list, args.len);
                errdefer comptime unreachable;
                for (value.as.char_list, args) |*v, a| v.* = a.as.char;
                return value;
            },
            .char_list => {},
            .symbol => {
                const value = try vm.allocValue(.symbol_list, args.len);
                errdefer comptime unreachable;
                for (value.as.symbol_list, args) |*v, a| v.* = a.as.symbol;
                return value;
            },
            .symbol_list => {},
            .dict => return error.nyi,
            .lambda => {},
            .unary_primitive => {},
            .operator => {},
            .projection => {},
        }
    }

    const value = try vm.allocValue(.list, args.len);
    errdefer comptime unreachable;
    for (value.as.list, args) |*v, a| v.* = a.ref();
    return value;
}

pub fn show(vm: *Vm, x: *Value) !*Value {
    std.log.debug("show", .{});
    try vm.stdout.print("{f}\n", .{x.alt(vm)});
    try vm.stdout.flush();
    return x.ref();
}

pub fn stringify(vm: *Vm, x: *Value) !*Value {
    const slice = try std.fmt.allocPrint(vm.gpa, "{f}", .{x.alt(vm)});
    errdefer vm.gpa.free(slice);
    return vm.createValue(.char_list, slice);
}

pub fn parse(vm: *Vm, x: *Value) !*Value {
    assert(x.as == .char_list);

    const slice = try vm.gpa.dupeSentinel(u8, x.as.char_list, 0);
    defer vm.gpa.free(slice);

    var tree: Ast = try .parse(vm.gpa, slice);
    defer tree.deinit(vm.gpa);
    if (tree.errors.len > 0) {
        try zk.printAstErrorsToStderr(vm.gpa, vm.io, tree, "<parse>", .auto);
        return error.parse;
    }

    return vm.parseTree(&tree);
}

pub fn eval(vm: *Vm, x: *Value) Error!*Value {
    std.log.debug("eval: {f}", .{x.alt(vm)});
    switch (x.as) {
        .list => |value| {
            if (value.len == 1 and value[0].as == .symbol_list) return value[0].ref();

            if (value[0].as == .char and value[0].as.char == ';') {
                for (value[1 .. value.len - 1]) |val| {
                    const v = try vm.eval(val);
                    defer v.deref(vm.gpa);
                }
                return vm.eval(value[value.len - 1]);
            }

            if (value[0].as == .operator and value[0].as.operator == .assign) {
                if (value.len != 3) return error.rank;
                switch (value[1].as) {
                    .symbol => |identifier| {
                        // TODO: Namespaces
                        if (std.mem.findScalar(Symbol, vm.state.as.dict.keys.as.symbol_list, identifier)) |index| {
                            _ = index; // autofix
                            @panic("NYI: variable reassignment");
                        } else {
                            const new_value = try vm.eval(value[2]);
                            errdefer new_value.deref(vm.gpa);

                            // TODO: Resize slices
                            const new_len = vm.state.as.dict.keys.as.symbol_list.len + 1;

                            const dict = try vm.createValue(.dict, .{ .keys = undefined, .values = undefined });
                            errdefer vm.gpa.destroy(dict);

                            const keys = try vm.allocValue(.symbol_list, new_len);
                            errdefer keys.deref(vm.gpa);
                            @memcpy(keys.as.symbol_list[0 .. new_len - 1], vm.state.as.dict.keys.as.symbol_list);
                            keys.as.symbol_list[new_len - 1] = identifier;
                            dict.as.dict.keys = keys;

                            const values = try vm.allocValue(.list, new_len);
                            errdefer comptime unreachable;
                            for (values.as.list[0 .. new_len - 1], vm.state.as.dict.values.as.list) |*new_v, old_v| {
                                new_v.* = old_v.ref();
                            }
                            values.as.list[new_len - 1] = new_value;
                            dict.as.dict.values = values;

                            vm.state.deref(vm.gpa);
                            vm.state = dict;

                            return new_value.ref();
                        }
                    },
                    inline else => |_, t| @panic("NYI: " ++ @tagName(t)),
                }
            }

            var it = std.mem.reverseIterator(value);
            while (it.next()) |entry| vm.push(try vm.eval(entry));

            const stack = vm.stack.items[vm.stack.items.len - value.len ..];
            defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - value.len);
            defer for (stack) |v| v.deref(vm.gpa);

            // TODO: Remove reverse
            std.mem.reverse(*Value, stack);
            const func = stack[0];
            const args = stack[1..];

            return vm.applyImpl(func, args);
        },
        .symbol => |identifier| {
            // TODO: Namespaces
            if (std.mem.findScalar(Symbol, vm.state.as.dict.keys.as.symbol_list, identifier)) |index| {
                return vm.state.as.dict.values.as.list[index].ref();
            } else return error.identifier; // TODO: Improve error message
        },
        .symbol_list => |value| {
            assert(value.len == 1);
            return vm.createValue(.symbol, value[0]);
        },
        else => return x.ref(),
    }
}

fn parseNode(vm: *Vm, node: Ast.Node.Index) ParseError!*Value {
    const tree = vm.tree;
    const gpa = vm.gpa;

    switch (tree.nodeTag(node)) {
        .root => {
            const nodes = tree.extraDataSlice(tree.nodeData(.root).extra_range, Ast.Node.Index);
            assert(nodes.len > 0);
            if (nodes.len == 1) return vm.parseNode(nodes[0]);

            var values: std.ArrayList(*Value) = try .initCapacity(gpa, nodes.len + 1);
            defer values.deinit(gpa);
            errdefer for (values.items) |v| v.deref(gpa);

            values.appendAssumeCapacity(vm.getConstant(.semicolon));
            for (nodes) |n| values.appendAssumeCapacity(try vm.parseNode(n));

            return vm.createValue(.list, values.toOwnedSliceAssert());
        },
        .empty => return vm.getUnaryPrimitive(.empty),

        .grouped_expression => return vm.parseNode(tree.nodeData(node).node_and_token[0]),
        .empty_list => return vm.allocValue(.list, 0),
        .list => {
            const nodes = tree.extraDataSlice(tree.nodeData(node).extra_range, Ast.Node.Index);

            var values: std.ArrayList(*Value) = try .initCapacity(gpa, nodes.len + 1);
            defer values.deinit(gpa);
            errdefer for (values.items) |v| v.deref(gpa);

            values.appendAssumeCapacity(vm.getUnaryPrimitive(.list));
            for (nodes) |n| values.appendAssumeCapacity(try vm.parseNode(n));

            return vm.createValue(.list, values.toOwnedSliceAssert());
        },
        .table_literal => @panic("NYI"),

        .lambda => @panic("NYI"),

        .expr_block => {
            const nodes = tree.extraDataSlice(tree.nodeData(node).extra_range, Ast.Node.Index);

            var values: std.ArrayList(*Value) = try .initCapacity(gpa, nodes.len + 1);
            defer values.deinit(gpa);
            errdefer for (values.items) |v| v.deref(gpa);

            values.appendAssumeCapacity(vm.getConstant(.semicolon));
            for (nodes) |n| values.appendAssumeCapacity(try vm.parseNode(n));

            return vm.createValue(.list, values.toOwnedSliceAssert());
        },

        .call => {
            const nodes = tree.extraDataSlice(tree.nodeData(node).extra_range, Ast.Node.Index);
            assert(nodes.len > 1);

            var values: std.ArrayList(*Value) = try .initCapacity(gpa, nodes.len);
            defer values.deinit(gpa);
            errdefer for (values.items) |v| v.deref(gpa);

            values.appendAssumeCapacity(try vm.parseNode(nodes[0]));
            if (nodes.len == 2 and tree.nodeTag(nodes[1]) == .empty) {
                values.appendAssumeCapacity(vm.getUnaryPrimitive(.identity));
            } else for (nodes[1..]) |n| values.appendAssumeCapacity(try vm.parseNode(n));

            return vm.createValue(.list, values.toOwnedSliceAssert());
        },
        .apply_unary => {
            const lhs, const rhs = tree.nodeData(node).node_and_node;

            var values: std.ArrayList(*Value) = try .initCapacity(gpa, 2);
            defer values.deinit(gpa);
            errdefer for (values.items) |v| v.deref(gpa);

            values.appendAssumeCapacity(try vm.parseUnaryNode(lhs));
            values.appendAssumeCapacity(try vm.parseNode(rhs));

            return vm.createValue(.list, values.toOwnedSliceAssert());
        },
        .apply_binary => {
            const lhs, const maybe_rhs = tree.nodeData(node).node_and_opt_node;
            const op: Ast.Node.Index = @enumFromInt(tree.nodeMainToken(node));

            var values: std.ArrayList(*Value) = try .initCapacity(gpa, 3);
            defer values.deinit(gpa);
            errdefer for (values.items) |v| v.deref(gpa);

            values.appendAssumeCapacity(try vm.parseNode(op));
            values.appendAssumeCapacity(try vm.parseNode(lhs));
            values.appendAssumeCapacity(if (maybe_rhs.unwrap()) |rhs|
                try vm.parseNode(rhs)
            else
                vm.getUnaryPrimitive(.empty));

            return vm.createValue(.list, values.toOwnedSliceAssert());
        },

        .bang => return vm.getOperator(.dict),
        .hash => return vm.getOperator(.take),
        .dollar => return vm.getOperator(.cast),
        .percent => return vm.getOperator(.divide),
        .ampersand => return vm.getOperator(.@"and"),
        .asterisk => return vm.getOperator(.multiply),
        .plus => return vm.getOperator(.add),
        .comma => return vm.getOperator(.join),
        .minus => return vm.getOperator(.subtract),
        .dot => return vm.getOperator(.apply),
        .colon => return vm.getOperator(.assign),
        .angle_bracket_left => return vm.getOperator(.less_than),
        .equals => return vm.getOperator(.equals),
        .angle_bracket_right => return vm.getOperator(.greater_than),
        .question_mark => return vm.getOperator(.find),
        .at => return vm.getOperator(.apply_at),
        .caret => return vm.getOperator(.fill),
        .underscore => return vm.getOperator(.drop),
        .pipe => return vm.getOperator(.@"or"),
        .tilde => return vm.getOperator(.match),

        .bang_colon => return vm.getUnaryPrimitive(.key),
        .hash_colon => return vm.getUnaryPrimitive(.count),
        .dollar_colon => return vm.getUnaryPrimitive(.string),
        .percent_colon => return vm.getUnaryPrimitive(.reciprocal),
        .ampersand_colon => return vm.getUnaryPrimitive(.where),
        .asterisk_colon => return vm.getUnaryPrimitive(.first),
        .plus_colon => return vm.getUnaryPrimitive(.flip),
        .comma_colon => return vm.getUnaryPrimitive(.list),
        .minus_colon => return vm.getUnaryPrimitive(.neg),
        .dot_colon => return vm.getUnaryPrimitive(.value),
        .colon_colon => return vm.getUnaryPrimitive(.identity),
        .angle_bracket_left_colon => return vm.getUnaryPrimitive(.asc),
        .equals_colon => return vm.getUnaryPrimitive(.group),
        .angle_bracket_right_colon => return vm.getUnaryPrimitive(.desc),
        .question_mark_colon => return vm.getUnaryPrimitive(.distinct),
        .at_colon => return vm.getUnaryPrimitive(.type),
        .caret_colon => return vm.getUnaryPrimitive(.null),
        .underscore_colon => return vm.getUnaryPrimitive(.lower),
        .pipe_colon => return vm.getUnaryPrimitive(.reverse),
        .tilde_colon => return vm.getUnaryPrimitive(.not),

        .apostrophe => @panic("NYI"),
        .apostrophe_colon => @panic("NYI"),
        .slash => @panic("NYI"),
        .slash_colon => @panic("NYI"),
        .backslash => @panic("NYI"),
        .backslash_colon => @panic("NYI"),

        .number_literal => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);
            if (Long.parse(slice)) |long| {
                return vm.createValue(.long, @intFromEnum(long));
            } else |_| {
                return vm.createValue(.float, try std.fmt.parseFloat(f64, slice));
            }
        },
        .number_list_literal => {
            const first_token = tree.nodeMainToken(node);
            const last_token = tree.nodeData(node).token;
            const number_list = list: {
                const long_list = try vm.allocValue(.long_list, last_token - first_token + 1);
                defer long_list.deref(gpa);
                for (first_token..last_token + 1, 0..) |tok, i| {
                    const slice = tree.tokenSlice(@intCast(tok));
                    if (Long.parse(slice)) |long| {
                        long_list.as.long_list[i] = @intFromEnum(long);
                    } else |_| {
                        const float_list = try vm.allocValue(.float_list, last_token - first_token + 1);
                        errdefer float_list.deref(gpa);
                        for (float_list.as.float_list[0..i], long_list.as.long_list[0..i]) |*f, l| f.* = @floatFromInt(l);
                        for (tok..last_token + 1, i..) |inner_tok, inner_i| {
                            const inner_slice = tree.tokenSlice(@intCast(inner_tok));
                            float_list.as.float_list[inner_i] = try std.fmt.parseFloat(f64, inner_slice);
                        }
                        break :list float_list;
                    }
                }
                break :list long_list.ref();
            };
            return number_list;
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
            if (buffered.len == 1) return vm.createValue(.char, buffered[0]);
            const char_list = try vm.allocValue(.char_list, buffered.len);
            errdefer comptime unreachable;
            @memcpy(char_list.as.char_list, buffered);
            return char_list;
        },
        .multiline_string_literal => {
            const first_token = tree.nodeMainToken(node);
            const last_token = tree.nodeData(node).token;
            var list: std.ArrayList(u8) = .empty;
            defer list.deinit(gpa);
            for (first_token..last_token + 1, 0..) |tok, i| {
                const slice = tree.tokenSlice(@intCast(tok));
                try list.appendSlice(gpa, slice[2..]);
                if (i < last_token) try list.append(gpa, '\n');
            }
            try list.shrinkToLen(gpa);
            return vm.createValue(.char_list, list.toOwnedSliceAssert());
        },
        .symbol_literal => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);
            const symbol = try vm.intern(slice[1..]);
            const symbol_list = try vm.allocValue(.symbol_list, 1);
            errdefer comptime unreachable;
            symbol_list.as.symbol_list[0] = symbol;
            return symbol_list;
        },
        .symbol_list_literal => {
            const first_token = tree.nodeMainToken(node);
            const last_token = tree.nodeData(node).token;
            const symbol_list = try vm.allocValue(.symbol_list, last_token - first_token + 1);
            errdefer symbol_list.deref(gpa);
            for (first_token..last_token + 1, 0..) |tok, i| {
                const slice = tree.tokenSlice(@intCast(tok));
                const symbol = try vm.intern(slice[1..]);
                symbol_list.as.symbol_list[i] = symbol;
            }
            const value = try vm.allocValue(.list, 1);
            errdefer comptime unreachable;
            value.as.list[0] = symbol_list;
            return value;
        },
        .identifier => {
            const main_token = tree.nodeMainToken(node);
            const slice = tree.tokenSlice(main_token);
            const symbol = try vm.intern(slice);
            return vm.createValue(.symbol, symbol);
        },
    }
}

fn parseUnaryNode(vm: *Vm, node: Ast.Node.Index) !*Value {
    const tree = vm.tree;

    switch (tree.nodeTag(node)) {
        .bang => return vm.getUnaryPrimitive(.key),
        .hash => return vm.getUnaryPrimitive(.count),
        .dollar => return vm.getUnaryPrimitive(.string),
        .percent => return vm.getUnaryPrimitive(.reciprocal),
        .ampersand => return vm.getUnaryPrimitive(.where),
        .asterisk => return vm.getUnaryPrimitive(.first),
        .plus => return vm.getUnaryPrimitive(.flip),
        .comma => return vm.getUnaryPrimitive(.list),
        .minus => return vm.getUnaryPrimitive(.neg),
        .dot => return vm.getUnaryPrimitive(.value),
        .colon => return vm.getUnaryPrimitive(.identity),
        .angle_bracket_left => return vm.getUnaryPrimitive(.asc),
        .equals => return vm.getUnaryPrimitive(.group),
        .angle_bracket_right => return vm.getUnaryPrimitive(.desc),
        .question_mark => return vm.getUnaryPrimitive(.distinct),
        .at => return vm.getUnaryPrimitive(.type),
        .caret => return vm.getUnaryPrimitive(.null),
        .underscore => return vm.getUnaryPrimitive(.lower),
        .pipe => return vm.getUnaryPrimitive(.reverse),
        .tilde => return vm.getUnaryPrimitive(.not),

        else => return vm.parseNode(node),
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

pub fn createValue(vm: *Vm, comptime tag: Value.Type, value: @FieldType(Value.Union, @tagName(tag))) !*Value {
    const self = try vm.gpa.create(Value);
    errdefer comptime unreachable;
    self.* = .{ .as = @unionInit(Value.Union, @tagName(tag), value) };
    return self;
}

pub fn allocValue(vm: *Vm, comptime tag: Value.Type, len: usize) !*Value {
    const T = @typeInfo(@FieldType(Value.Union, @tagName(tag))).pointer.child;
    const value = try vm.gpa.alloc(T, len);
    errdefer vm.gpa.free(value);
    return vm.createValue(tag, value);
}

test {
    std.testing.refAllDecls(@This());
}

fn testVm(source: [:0]const u8, comptime tag: Value.Type, expected: anytype) !void {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var stdout_writer = Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    var vm: *Vm = try .init(io, gpa, stdout);
    defer vm.deinit();

    var tree: Ast = try .parse(gpa, source);
    defer tree.deinit(gpa);

    try std.testing.expectEqual(0, tree.errors.len);

    const value = try vm.evalTree(&tree);
    defer value.deref(gpa);

    try std.testing.expectEqual(tag, @as(Value.Type, value.as));

    const T = @FieldType(Value.Union, @tagName(tag));
    switch (tag) {
        .list,
        .boolean_list,
        .long_list,
        .float_list,
        .char_list,
        .symbol_list,
        => try std.testing.expectEqualSlices(@typeInfo(T).pointer.child, expected, @field(value.as, @tagName(tag))),
        .boolean,
        .long,
        .float,
        .char,
        .symbol,
        .unary_primitive,
        .operator,
        => try std.testing.expectEqual(expected, @field(value.as, @tagName(tag))),
        .projection,
        => {
            try std.testing.expectEqual(expected.callee, @as(Value.Type, value.as.projection.callee.as));
            try std.testing.expectEqual(expected.args, value.as.projection.args.len);
        },
        .dict,
        .lambda,
        => @panic("NYI: " ++ @tagName(tag)),
    }
}

test "parse/eval" {
    try testVm(
        \\-6!-5!"-6!-5!\"3*4+5\""
    , .long, 27);
}

test "number list literal with null/inf" {
    const long_null = @intFromEnum(Long.null);
    const long_neg_inf = @intFromEnum(Long.neg_inf);
    const long_inf = @intFromEnum(Long.inf);
    try testVm("1 2 0n 0N -0w -0W 0w 0W 3 4", .long_list, &.{
        1, 2, long_null, long_null, long_neg_inf, long_neg_inf, long_inf, long_inf, 3, 4,
    });
}

test "projections" {
    try testVm("+[1][2]", .long, 3);
    try testVm("+[1;][2]", .long, 3);
    try testVm("+[;2][1]", .long, 3);
    try testVm("+[;][1]", .projection, .{ .callee = .operator, .args = 1 });
    try testVm("+[;][1;]", .projection, .{ .callee = .operator, .args = 2 });
    try testVm("+[;][;2]", .projection, .{ .callee = .operator, .args = 2 });
    try testVm("+[;][;]", .projection, .{ .callee = .operator, .args = 2 });
}
