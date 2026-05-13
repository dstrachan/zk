const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Color = std.zig.Color;
const ErrorBundle = std.zig.ErrorBundle;
const Span = std.zig.Ast.Span;
const assert = std.debug.assert;

const tokenizer = @import("tokenizer.zig");
pub const Token = tokenizer.Token;
pub const Tokenizer = tokenizer.Tokenizer;
pub const Ast = @import("Ast.zig");
pub const Parse = @import("Parse.zig");
pub const Vm = @import("Vm.zig");
pub const Value = @import("Value.zig");

pub fn printAstErrorsToStderr(gpa: Allocator, io: Io, tree: Ast, path: []const u8, color: Color) !void {
    var wip_errors: ErrorBundle.Wip = undefined;
    try wip_errors.init(gpa);
    defer wip_errors.deinit();

    try putAstErrorsIntoBundle(gpa, tree, path, &wip_errors);

    var error_bundle = try wip_errors.toOwnedBundle("");
    defer error_bundle.deinit(gpa);
    return error_bundle.renderToStderr(io, .{}, color);
}

pub fn putAstErrorsIntoBundle(gpa: Allocator, tree: Ast, src_path: []const u8, eb: *ErrorBundle.Wip) !void {
    assert(tree.errors.len > 0);

    var msg: Io.Writer.Allocating = .init(gpa);
    defer msg.deinit();
    const msg_w = &msg.writer;

    for (tree.errors) |err| {
        const err_span: Span = blk: {
            const start = tree.tokenStart(err.token);
            const end = start + @as(u32, @intCast(tree.tokenSlice(err.token).len));
            break :blk .{ .start = start, .end = end, .main = start };
        };
        const err_loc = std.zig.findLineColumn(tree.source, err_span.main);

        try tree.renderError(err, msg_w);
        try eb.addRootErrorMessage(.{
            .msg = try eb.addString(msg.written()),
            .src_loc = try eb.addSourceLocation(.{
                .src_path = try eb.addString(src_path),
                .span_start = err_span.start,
                .span_main = err_span.main,
                .span_end = err_span.end,
                .line = @intCast(err_loc.line),
                .column = @intCast(err_loc.column),
                .source_line = try eb.addString(err_loc.source_line),
            }),
            .notes_len = 0,
        });
        msg.clearRetainingCapacity();
    }
}

test {
    std.testing.refAllDecls(@This());
}
