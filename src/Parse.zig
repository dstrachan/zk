const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zk = @import("root.zig");
const Ast = zk.Ast;
const TokenIndex = Ast.TokenIndex;
const Node = Ast.Node;
const AstError = Ast.Error;
const Token = zk.Token;
const ExtraIndex = Ast.ExtraIndex;
const OptionalTokenIndex = Ast.OptionalTokenIndex;
const Tokenizer = zk.Tokenizer;

const Parse = @This();

pub const Error = error{ParseError} || Allocator.Error;

gpa: Allocator,
source: [:0]const u8,
tokens: Ast.TokenList.Slice,
tok_i: TokenIndex,
errors: std.ArrayList(AstError),
nodes: Ast.NodeList,
extra_data: std.ArrayList(u32),
scratch: std.ArrayList(Node.Index),

fn tokenTag(p: *const Parse, token_index: TokenIndex) Token.Tag {
    return p.tokens.items(.tag)[token_index];
}

fn tokenStart(p: *const Parse, token_index: TokenIndex) Ast.ByteOffset {
    return p.tokens.items(.start)[token_index];
}

fn nodeTag(p: *const Parse, node: Node.Index) Node.Tag {
    return p.nodes.items(.tag)[@intFromEnum(node)];
}

fn nodeMainToken(p: *const Parse, node: Node.Index) TokenIndex {
    return p.nodes.items(.main_token)[@intFromEnum(node)];
}

fn nodeData(p: *const Parse, node: Node.Index) Node.Data {
    return p.nodes.items(.data)[@intFromEnum(node)];
}

fn tokenSlice(p: *const Parse, token_index: TokenIndex) []const u8 {
    const token_tag = p.tokenTag(token_index);

    // Many tokens can be determined entirely by their tag.
    if (token_tag.lexeme()) |lexeme| {
        return lexeme;
    }

    // For some tokens, re-tokenization is needed to find the end.
    var tokenizer: Tokenizer = .{
        .buffer = p.source,
        .index = p.tokenStart(token_index),
    };
    const token = tokenizer.next();
    assert(token.tag == token_tag);
    return p.source[token.loc.start..token.loc.end];
}

fn isNoun(p: *const Parse, node: Node.Index) bool {
    return switch (p.nodeTag(node)) {
        .grouped_expression,
        .empty_list,
        .list,
        .table_literal,
        .lambda,
        .expr_block,
        .call,
        .number_literal,
        .number_list_literal,
        .string_literal,
        .multiline_string_literal,
        .symbol_literal,
        .symbol_list_literal,
        .identifier,
        => true,
        else => false,
    };
}

const Exprs = struct {
    len: usize,
    /// Must be either `.opt_node_and_opt_node` if `len <= 2` or `.extra_range` otherwise.
    data: Node.Data,

    fn toSpan(self: Exprs, p: *Parse) !Node.SubRange {
        return switch (self.len) {
            0 => p.listToSpan(&.{}),
            1 => p.listToSpan(&.{self.data.opt_node_and_opt_node[0].unwrap().?}),
            2 => p.listToSpan(&.{ self.data.opt_node_and_opt_node[0].unwrap().?, self.data.opt_node_and_opt_node[1].unwrap().? }),
            else => self.data.extra_range,
        };
    }
};

fn listToSpan(p: *Parse, list: []const Node.Index) Allocator.Error!Node.SubRange {
    try p.extra_data.appendSlice(p.gpa, @ptrCast(list));
    return .{
        .start = @enumFromInt(p.extra_data.items.len - list.len),
        .end = @enumFromInt(p.extra_data.items.len),
    };
}

fn addNode(p: *Parse, elem: Ast.Node) Allocator.Error!Node.Index {
    const result: Node.Index = @enumFromInt(p.nodes.len);
    try p.nodes.append(p.gpa, elem);
    return result;
}

fn setNode(p: *Parse, i: usize, elem: Ast.Node) Node.Index {
    p.nodes.set(i, elem);
    return @enumFromInt(i);
}

fn reserveNode(p: *Parse, tag: Ast.Node.Tag) !usize {
    try p.nodes.resize(p.gpa, p.nodes.len + 1);
    p.nodes.items(.tag)[p.nodes.len - 1] = tag;
    return p.nodes.len - 1;
}

fn unreserveNode(p: *Parse, node_index: usize) void {
    if (p.nodes.len == node_index) {
        p.nodes.resize(p.gpa, p.nodes.len - 1) catch unreachable;
    } else {
        // There is zombie node left in the tree, let's make it as inoffensive as possible
        p.nodes.items(.tag)[node_index] = .empty;
        p.nodes.items(.main_token)[node_index] = p.tok_i;
    }
}

fn addExtra(p: *Parse, extra: anytype) Allocator.Error!ExtraIndex {
    const fields = std.meta.fields(@TypeOf(extra));
    try p.extra_data.ensureUnusedCapacity(p.gpa, fields.len);
    const result: ExtraIndex = @enumFromInt(p.extra_data.items.len);
    inline for (fields) |field| {
        const data: u32 = switch (field.type) {
            bool => @intFromBool(@field(extra, field.name)),
            Node.Index,
            Node.OptionalIndex,
            OptionalTokenIndex,
            ExtraIndex,
            => @intFromEnum(@field(extra, field.name)),
            TokenIndex,
            => @field(extra, field.name),
            else => |t| @compileError("unexpected field type - " ++ @typeName(t)),
        };
        p.extra_data.appendAssumeCapacity(data);
    }
    return result;
}

fn warnExpected(p: *Parse, expected_token: Token.Tag) error{OutOfMemory}!void {
    @branchHint(.cold);
    try p.warnMsg(.{
        .tag = .expected_token,
        .token = p.tok_i,
        .extra = .{ .expected_tag = expected_token },
    });
}

fn warn(p: *Parse, error_tag: AstError.Tag) error{OutOfMemory}!void {
    @branchHint(.cold);
    try p.warnMsg(.{ .tag = error_tag, .token = p.tok_i });
}

fn warnMsg(p: *Parse, msg: Ast.Error) error{OutOfMemory}!void {
    @branchHint(.cold);
    try p.errors.append(p.gpa, msg);
}

fn fail(p: *Parse, tag: Ast.Error.Tag) Error {
    @branchHint(.cold);
    return p.failMsg(.{ .tag = tag, .token = p.tok_i });
}

fn failExpected(p: *Parse, expected_token: Token.Tag) Error {
    @branchHint(.cold);
    return p.failMsg(.{
        .tag = .expected_token,
        .token = p.tok_i,
        .extra = .{ .expected_tag = expected_token },
    });
}

fn failMsg(p: *Parse, msg: Ast.Error) Error {
    @branchHint(.cold);
    try p.warnMsg(msg);
    return error.ParseError;
}

pub fn deinit(p: *Parse) void {
    p.scratch.deinit(p.gpa);
    p.extra_data.deinit(p.gpa);
    p.nodes.deinit(p.gpa);
    p.errors.deinit(p.gpa);
}

pub fn parseRoot(p: *Parse) !void {
    // Root node must be index 0.
    p.nodes.appendAssumeCapacity(.{
        .tag = .root,
        .main_token = 0,
        .data = undefined,
    });
    const root_exprs = try p.parseExprs();
    if (p.tokenTag(p.tok_i) != .eof) {
        try p.warnExpected(.eof);
    }
    p.nodes.items(.data)[0] = .{ .extra_range = try root_exprs.toSpan(p) };
}

fn parseExprs(p: *Parse) Allocator.Error!Exprs {
    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    while (true) {
        switch (p.tokenTag(p.tok_i)) {
            .invalid => {
                try p.warn(.expected_expr);
                _ = p.nextToken();
                break;
            },
            .eos => _ = p.nextToken(),
            .eof => break,
            else => {},
        }

        const expr = p.parseExpr() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => blk: {
                p.skipExpr();
                break :blk .none;
            },
        };
        if (expr.unwrap()) |node| try p.scratch.append(p.gpa, node);
        _ = p.eatToken(.semicolon);
    }

    const items = p.scratch.items[scratch_top..];
    return .{
        .len = items.len,
        .data = switch (items.len) {
            0, 1, 2 => .{ .opt_node_and_opt_node = .{
                if (items.len > 0) items[0].toOptional() else .none,
                if (items.len > 1) items[1].toOptional() else .none,
            } },
            else => .{ .extra_range = try p.listToSpan(items) },
        },
    };
}

fn expectExpr(p: *Parse) !Node.Index {
    const expr = try p.parseExpr();
    return expr.unwrap() orelse p.fail(.expected_expr);
}

fn parseExpr(p: *Parse) Error!Node.OptionalIndex {
    const noun = try p.parseNoun();
    var node = noun.unwrap() orelse return .none;

    while (true) {
        const verb = try p.parseVerb(node);
        node = verb.unwrap() orelse break;
    }

    return node.toOptional();
}

fn endsExpr(p: *Parse) bool {
    return switch (p.tokenTag(p.tok_i)) {
        .r_paren, .r_bracket, .r_brace, .semicolon, .eos, .eof => true,
        else => blk: {
            const start = p.tokenStart(p.tok_i + 1);
            break :blk p.source[start - 1] == '\n';
        },
    };
}

fn expectNoun(p: *Parse) !Node.Index {
    const noun = try p.parseNoun();
    return noun.unwrap() orelse p.fail(.expected_noun);
}

fn parseNoun(p: *Parse) Error!Node.OptionalIndex {
    const noun = switch (p.tokenTag(p.tok_i)) {
        .l_paren => try p.parseGroup(),
        .r_paren => return .none,
        .l_bracket => try p.parseBlock(),
        .r_bracket => return .none,
        .l_brace => try p.parseLambda(),
        .r_brace => return .none,
        .semicolon => return .none,

        .bang => try p.addNoun(.bang),
        .hash => try p.addNoun(.hash),
        .dollar => try p.addNoun(.dollar),
        .percent => try p.addNoun(.percent),
        .ampersand => try p.addNoun(.ampersand),
        .asterisk => try p.addNoun(.asterisk),
        .plus => try p.addNoun(.plus),
        .comma => try p.addNoun(.comma),
        .minus => try p.addNoun(.minus),
        .dot => try p.addNoun(.dot),
        .colon => try p.addNoun(.colon),
        .angle_bracket_left => try p.addNoun(.angle_bracket_left),
        .equals => try p.addNoun(.equals),
        .angle_bracket_right => try p.addNoun(.angle_bracket_right),
        .question_mark => try p.addNoun(.question_mark),
        .at => try p.addNoun(.at),
        .caret => try p.addNoun(.caret),
        .underscore => try p.addNoun(.underscore),
        .pipe => try p.addNoun(.pipe),
        .tilde => try p.addNoun(.tilde),

        .bang_colon => try p.addNoun(.bang_colon),
        .hash_colon => try p.addNoun(.hash_colon),
        .dollar_colon => try p.addNoun(.dollar_colon),
        .percent_colon => try p.addNoun(.percent_colon),
        .ampersand_colon => try p.addNoun(.ampersand_colon),
        .asterisk_colon => try p.addNoun(.asterisk_colon),
        .plus_colon => try p.addNoun(.plus_colon),
        .comma_colon => try p.addNoun(.comma_colon),
        .minus_colon => try p.addNoun(.minus_colon),
        .dot_colon => try p.addNoun(.dot_colon),
        .colon_colon => try p.addNoun(.colon_colon),
        .angle_bracket_left_colon => try p.addNoun(.angle_bracket_left_colon),
        .equals_colon => try p.addNoun(.equals_colon),
        .angle_bracket_right_colon => try p.addNoun(.angle_bracket_right_colon),
        .question_mark_colon => try p.addNoun(.question_mark_colon),
        .at_colon => try p.addNoun(.at_colon),
        .caret_colon => try p.addNoun(.caret_colon),
        .underscore_colon => try p.addNoun(.underscore_colon),
        .pipe_colon => try p.addNoun(.pipe_colon),
        .tilde_colon => try p.addNoun(.tilde_colon),

        .apostrophe => try p.addIterator(.apostrophe, .none),
        .slash => try p.addIterator(.slash, .none),
        .backslash => try p.addIterator(.backslash, .none),
        .apostrophe_colon => try p.addIterator(.apostrophe_colon, .none),
        .slash_colon => try p.addIterator(.slash_colon, .none),
        .backslash_colon => try p.addIterator(.backslash_colon, .none),

        .identifier => try p.addNoun(.identifier),
        .number_literal => try p.parseNumberLiteral(),
        .string_literal => try p.addNoun(.string_literal),
        .multiline_string_literal => try p.parseMultilineStringLiteral(),
        .symbol_literal => try p.parseSymbolLiteral(),

        .invalid => return p.fail(.expected_expr),
        .eos => return .none,
        .eof => return .none,
    };
    const call = try p.parseCall(noun);
    return call.toOptional();
}

fn expectVerb(p: *Parse, lhs: Node.Index) !Node.Index {
    const verb = try p.parseVerb(lhs);
    return verb.unwrap() orelse p.fail(.expected_verb);
}

fn parseVerb(p: *Parse, lhs: Node.Index) Error!Node.OptionalIndex {
    if (p.endsExpr()) return .none;

    const verb = switch (p.tokenTag(p.tok_i)) {
        .l_paren => try p.parseUnary(lhs),
        .r_paren => unreachable,
        .l_bracket => unreachable,
        .r_bracket => unreachable,
        .l_brace => try p.parseUnary(lhs),
        .r_brace => unreachable,
        .semicolon => unreachable,

        .bang,
        .hash,
        .dollar,
        .percent,
        .ampersand,
        .asterisk,
        .plus,
        .comma,
        .minus,
        .dot,
        .colon,
        .angle_bracket_left,
        .equals,
        .angle_bracket_right,
        .question_mark,
        .at,
        .caret,
        .underscore,
        .pipe,
        .tilde,
        => try if (p.isNoun(lhs)) p.parseBinary(lhs) else p.parseUnary(lhs),

        .bang_colon,
        .hash_colon,
        .dollar_colon,
        .percent_colon,
        .ampersand_colon,
        .asterisk_colon,
        .plus_colon,
        .comma_colon,
        .minus_colon,
        .dot_colon,
        .colon_colon,
        .angle_bracket_left_colon,
        .equals_colon,
        .angle_bracket_right_colon,
        .question_mark_colon,
        .at_colon,
        .caret_colon,
        .underscore_colon,
        .pipe_colon,
        .tilde_colon,
        => try p.parseUnary(lhs),

        .apostrophe => unreachable,
        .slash => unreachable,
        .backslash => unreachable,
        .apostrophe_colon => unreachable,
        .slash_colon => unreachable,
        .backslash_colon => unreachable,

        .identifier,
        .number_literal,
        .string_literal,
        .multiline_string_literal,
        .symbol_literal,
        => try p.parseUnary(lhs),

        .invalid => return p.fail(.expected_expr),
        .eos => unreachable,
        .eof => unreachable,
    };
    return verb.toOptional();
}

fn parseUnary(p: *Parse, lhs: Node.Index) !Node.Index {
    const apply_index = try p.reserveNode(.apply_unary);
    errdefer p.unreserveNode(apply_index);

    const rhs = try p.expectNoun();
    switch (p.nodeTag(rhs)) {
        .apostrophe,
        .apostrophe_colon,
        .slash,
        .slash_colon,
        .backslash,
        .backslash_colon,
        => return p.setNode(apply_index, .{
            .tag = .apply_binary,
            .main_token = @intFromEnum(rhs),
            .data = .{ .node_and_opt_node = .{ lhs, try p.parseExpr() } },
        }),
        else => {
            const verb = try p.parseVerb(rhs);
            return p.setNode(apply_index, .{
                .tag = .apply_unary,
                .main_token = undefined,
                .data = .{ .node_and_node = .{ lhs, verb.unwrap() orelse rhs } },
            });
        },
    }
}

fn parseBinary(p: *Parse, lhs: Node.Index) !Node.Index {
    const apply_index = try p.reserveNode(.apply_binary);
    errdefer p.unreserveNode(apply_index);

    const op = try p.expectNoun();
    return p.setNode(apply_index, .{
        .tag = .apply_binary,
        .main_token = @intFromEnum(op),
        .data = .{ .node_and_opt_node = .{ lhs, try p.parseExpr() } },
    });
}

fn parseCall(p: *Parse, lhs: Node.Index) Error!Node.Index {
    if (p.tokenTag(p.tok_i) != .l_bracket) return p.parseIterator(lhs);

    const l_bracket = p.assertToken(.l_bracket);

    const call_index = try p.reserveNode(.call);
    errdefer p.unreserveNode(call_index);

    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    try p.scratch.append(p.gpa, lhs);

    while (true) {
        const expr = try p.parseExpr();
        try p.scratch.append(p.gpa, expr.unwrap() orelse try p.empty());
        _ = p.eatToken(.semicolon) orelse break;
    }
    _ = try p.expectToken(.r_bracket);

    const args = p.scratch.items[scratch_top..];
    return p.parseCall(p.setNode(call_index, .{
        .tag = .call,
        .main_token = l_bracket,
        .data = .{ .extra_range = try p.listToSpan(args) },
    }));
}

fn parseIterator(p: *Parse, lhs: Node.Index) !Node.Index {
    const tag: Node.Tag = switch (p.tokenTag(p.tok_i)) {
        .apostrophe => .apostrophe,
        .apostrophe_colon => .apostrophe_colon,
        .slash => .slash,
        .slash_colon => .slash_colon,
        .backslash => .backslash,
        .backslash_colon => .backslash_colon,
        else => return lhs,
    };
    const iterator = try p.addNode(.{
        .tag = tag,
        .main_token = p.nextToken(),
        .data = .{ .opt_node = lhs.toOptional() },
    });
    return p.parseCall(iterator);
}

fn parseGroup(p: *Parse) !Node.Index {
    const l_paren = p.assertToken(.l_paren);
    if (p.tokenTag(p.tok_i) == .l_bracket) @panic("NYI: table");

    const group_index = try p.reserveNode(.grouped_expression);
    errdefer p.unreserveNode(group_index);

    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    if (p.tokenTag(p.tok_i) != .r_paren) {
        while (true) {
            const expr = try p.parseExpr();
            try p.scratch.append(p.gpa, expr.unwrap() orelse try p.empty());
            _ = p.eatToken(.semicolon) orelse break;
        }
    }
    const r_paren = try p.expectToken(.r_paren);

    const list = p.scratch.items[scratch_top..];
    return switch (list.len) {
        0 => p.setNode(group_index, .{
            .tag = .empty_list,
            .main_token = l_paren,
            .data = undefined,
        }),
        1 => p.setNode(group_index, .{
            .tag = .grouped_expression,
            .main_token = l_paren,
            .data = .{ .node_and_token = .{ list[0], r_paren } },
        }),
        else => p.setNode(group_index, .{
            .tag = .list,
            .main_token = l_paren,
            .data = .{ .extra_range = try p.listToSpan(list) },
        }),
    };
}

fn parseBlock(p: *Parse) !Node.Index {
    const l_bracket = p.assertToken(.l_bracket);

    const block_index = try p.reserveNode(.expr_block);
    errdefer p.unreserveNode(block_index);

    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    if (p.tokenTag(p.tok_i) != .r_paren) {
        while (true) {
            const expr = try p.parseExpr();
            if (expr.unwrap()) |node| try p.scratch.append(p.gpa, node);
            _ = p.eatToken(.semicolon) orelse break;
        }
    }
    _ = try p.expectToken(.r_bracket);

    const nodes = p.scratch.items[scratch_top..];
    return p.setNode(block_index, .{
        .tag = .expr_block,
        .main_token = l_bracket,
        .data = .{ .extra_range = try p.listToSpan(nodes) },
    });
}

fn parseLambda(p: *Parse) !Node.Index {
    const l_brace = p.assertToken(.l_brace);

    const lambda_index = try p.reserveNode(.lambda);
    errdefer p.unreserveNode(lambda_index);

    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    const params_top = p.scratch.items.len;
    if (p.eatToken(.l_bracket)) |_| {
        if (p.tokenTag(p.tok_i) != .r_bracket) {
            while (true) {
                const expr = try p.expectExpr();
                try p.scratch.append(p.gpa, expr);
                _ = p.eatToken(.semicolon) orelse break;
            }
        } else {
            try p.scratch.append(p.gpa, try p.empty());
        }
        _ = try p.expectToken(.r_bracket);
    }

    const body_top = p.scratch.items.len;
    while (true) {
        const expr = try p.parseExpr();
        if (expr.unwrap()) |node| try p.scratch.append(p.gpa, node);
        _ = p.eatToken(.semicolon) orelse break;
    }
    const trailing_semicolon = p.tokenTag(p.tok_i - 1) == .semicolon;
    const r_brace = try p.expectToken(.r_brace);

    const params = try p.listToSpan(p.scratch.items[params_top..body_top]);
    const body = try p.listToSpan(p.scratch.items[body_top..]);
    const lambda: Node.Lambda = .{
        .params_start = params.start,
        .body_start = body.start,
        .body_end = body.end,
        .trailing_semicolon = trailing_semicolon,
    };
    return p.setNode(lambda_index, .{
        .tag = .lambda,
        .main_token = l_brace,
        .data = .{ .extra_and_token = .{ try p.addExtra(lambda), r_brace } },
    });
}

fn parseNumberLiteral(p: *Parse) !Node.Index {
    const first_token = p.assertToken(.number_literal);
    var last_token = first_token;

    while (p.tokenTag(p.tok_i) == .number_literal) {
        const slice = p.tokenSlice(last_token);
        switch (slice[slice.len - 1]) {
            'b' => break,
            else => {},
        }
        last_token = p.assertToken(.number_literal);
    }

    if (first_token == last_token) {
        return p.addNode(.{
            .tag = .number_literal,
            .main_token = first_token,
            .data = undefined,
        });
    } else {
        return p.addNode(.{
            .tag = .number_list_literal,
            .main_token = first_token,
            .data = .{ .token = last_token },
        });
    }
}

fn parseMultilineStringLiteral(p: *Parse) !Node.Index {
    const first_token = p.assertToken(.multiline_string_literal);
    var last_token = first_token;
    while (p.tokenTag(p.tok_i) == .multiline_string_literal) {
        last_token = p.assertToken(.multiline_string_literal);
    }
    return p.addNode(.{
        .tag = .multiline_string_literal,
        .main_token = first_token,
        .data = .{ .token = last_token },
    });
}

fn parseSymbolLiteral(p: *Parse) !Node.Index {
    const first_token = p.assertToken(.symbol_literal);
    var last_token = first_token;

    while (p.tokenTag(p.tok_i) == .symbol_literal) {
        if (p.tokenStart(p.tok_i) != p.tokenStart(last_token) + p.tokenSlice(last_token).len) break;
        last_token = p.assertToken(.symbol_literal);
    }

    if (first_token == last_token) {
        return p.addNode(.{
            .tag = .symbol_literal,
            .main_token = first_token,
            .data = undefined,
        });
    } else {
        return p.addNode(.{
            .tag = .symbol_list_literal,
            .main_token = first_token,
            .data = .{ .token = last_token },
        });
    }
}

fn empty(p: *Parse) !Node.Index {
    return p.addNode(.{
        .tag = .empty,
        .main_token = p.tok_i,
        .data = undefined,
    });
}

fn addNoun(p: *Parse, tag: Node.Tag) !Node.Index {
    return p.addNode(.{
        .tag = tag,
        .main_token = p.nextToken(),
        .data = undefined,
    });
}

fn addIterator(p: *Parse, tag: Node.Tag, lhs: Node.OptionalIndex) !Node.Index {
    return p.addNode(.{
        .tag = tag,
        .main_token = p.nextToken(),
        .data = .{ .opt_node = lhs },
    });
}

fn eatToken(p: *Parse, tag: Token.Tag) ?TokenIndex {
    return if (p.tokenTag(p.tok_i) == tag) p.nextToken() else null;
}

fn eatTokens(p: *Parse, tags: []const Token.Tag) ?TokenIndex {
    const available_tags = p.tokens.items(.tag)[p.tok_i..];
    if (!std.mem.startsWith(Token.Tag, available_tags, tags)) return null;
    const result = p.tok_i;
    p.tok_i += @intCast(tags.len);
    return result;
}

fn assertToken(p: *Parse, tag: Token.Tag) TokenIndex {
    const token = p.nextToken();
    assert(p.tokenTag(token) == tag);
    return token;
}

fn expectToken(p: *Parse, tag: Token.Tag) Error!TokenIndex {
    return if (p.tokenTag(p.tok_i) == tag) p.nextToken() else p.failExpected(tag);
}

fn nextToken(p: *Parse) TokenIndex {
    const token = p.tok_i;
    if (p.tok_i != p.tokens.len - 1) p.tok_i += 1;
    return token;
}

fn skipExpr(p: *Parse) void {
    while (true) {
        if (p.tokenTag(p.tok_i) == .eof) break;
        if (p.eatToken(.eos)) |_| break;
        _ = p.nextToken();
    }
}

test {
    std.testing.refAllDecls(@This());
}
