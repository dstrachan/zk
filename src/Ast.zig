const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zk = @import("root.zig");
const Token = zk.Token;
const Tokenizer = zk.Tokenizer;
const Parse = zk.Parse;

const Ast = @This();

/// Reference to externally-owned data.
source: [:0]const u8,

tokens: TokenList.Slice,
nodes: NodeList.Slice,
extra_data: []u32,

errors: []const Error,

pub const ByteOffset = u32;

pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: ByteOffset,
});
pub const NodeList = std.MultiArrayList(Node);

/// Index into `tokens`.
pub const TokenIndex = u32;

/// Index into `tokens`, or null.
pub const OptionalTokenIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn unwrap(oti: OptionalTokenIndex) ?TokenIndex {
        return if (oti == .none) null else @intFromEnum(oti);
    }

    pub fn fromToken(ti: TokenIndex) OptionalTokenIndex {
        return @enumFromInt(ti);
    }

    pub fn fromOptional(oti: ?TokenIndex) OptionalTokenIndex {
        return if (oti) |ti| @enumFromInt(ti) else .none;
    }
};

/// A relative token index.
pub const TokenOffset = enum(i32) {
    zero = 0,
    _,

    pub fn init(base: TokenIndex, destination: TokenIndex) TokenOffset {
        const base_i64: i64 = base;
        const destination_i64: i64 = destination;
        return @enumFromInt(destination_i64 - base_i64);
    }

    pub fn toOptional(to: TokenOffset) OptionalTokenOffset {
        const result: OptionalTokenOffset = @enumFromInt(@intFromEnum(to));
        assert(result != .none);
        return result;
    }

    pub fn toAbsolute(offset: TokenOffset, base: TokenIndex) TokenIndex {
        return @intCast(@as(i64, base) + @intFromEnum(offset));
    }
};

/// A relative token index, or null.
pub const OptionalTokenOffset = enum(i32) {
    none = std.math.maxInt(i32),
    _,

    pub fn unwrap(oto: OptionalTokenOffset) ?TokenOffset {
        return if (oto == .none) null else @enumFromInt(@intFromEnum(oto));
    }
};

pub fn tokenTag(tree: *const Ast, token_index: TokenIndex) Token.Tag {
    return tree.tokens.items(.tag)[token_index];
}

pub fn tokenStart(tree: *const Ast, token_index: TokenIndex) ByteOffset {
    return tree.tokens.items(.start)[token_index];
}

pub fn nodeTag(tree: *const Ast, node: Node.Index) Node.Tag {
    return tree.nodes.items(.tag)[@intFromEnum(node)];
}

pub fn nodeMainToken(tree: *const Ast, node: Node.Index) TokenIndex {
    return tree.nodes.items(.main_token)[@intFromEnum(node)];
}

pub fn nodeData(tree: *const Ast, node: Node.Index) Node.Data {
    return tree.nodes.items(.data)[@intFromEnum(node)];
}

pub fn tokenSlice(tree: Ast, token_index: TokenIndex) []const u8 {
    const token_tag = tree.tokenTag(token_index);

    // Many tokens can be determined entirely by their tag.
    if (token_tag.lexeme()) |lexeme| {
        return lexeme;
    }

    // For some tokens, re-tokenization is needed to find the end.
    var tokenizer: Tokenizer = .{
        .buffer = tree.source,
        .index = tree.tokenStart(token_index),
    };
    const token = tokenizer.next();
    assert(token.tag == token_tag);
    return tree.source[token.loc.start..token.loc.end];
}

pub fn extraDataSlice(tree: Ast, range: Node.SubRange, comptime T: type) []const T {
    return @ptrCast(tree.extra_data[@intFromEnum(range.start)..@intFromEnum(range.end)]);
}

pub fn deinit(tree: *Ast, gpa: Allocator) void {
    tree.tokens.deinit(gpa);
    tree.nodes.deinit(gpa);
    gpa.free(tree.extra_data);
    gpa.free(tree.errors);
    tree.* = undefined;
}

pub fn parse(gpa: Allocator, source: [:0]const u8) Allocator.Error!Ast {
    var tokens: Ast.TokenList = .{};
    defer tokens.deinit(gpa);

    // Empirically, the zig std lib has an 8:1 ratio of source bytes to token count.
    const estimated_token_count = source.len / 8;
    try tokens.ensureTotalCapacity(gpa, estimated_token_count);

    var tokenizer: Tokenizer = .init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, .{
            .tag = token.tag,
            .start = @intCast(token.loc.start),
        });
        if (token.tag == .eof) break;
    }

    var tokens_slice = tokens.toOwnedSlice();
    errdefer tokens_slice.deinit(gpa);
    return parseTokens(gpa, source, tokens_slice);
}

pub fn parseTokens(gpa: Allocator, source: [:0]const u8, tokens: TokenList.Slice) Allocator.Error!Ast {
    var parser: Parse = .{
        .gpa = gpa,
        .source = source,
        .tokens = tokens,
        .errors = .empty,
        .nodes = .empty,
        .extra_data = .empty,
        .scratch = .empty,
        .tok_i = 0,
    };
    defer parser.deinit();

    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (tokens.len + 2) / 2;
    try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    try parser.parseRoot();

    try parser.extra_data.shrinkToLen(gpa);
    try parser.errors.shrinkToLen(gpa);

    return .{
        .source = source,
        .tokens = tokens,
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = parser.extra_data.toOwnedSliceAssert(),
        .errors = parser.errors.toOwnedSliceAssert(),
    };
}

pub fn renderError(tree: Ast, parse_error: Error, w: *Io.Writer) Io.Writer.Error!void {
    switch (parse_error.tag) {
        .expected_expr => {
            return w.print("expected expression, found '{s}'", .{
                tree.tokenTag(parse_error.token).symbol(),
            });
        },
        .expected_noun => {
            return w.print("expected noun, found '{s}'", .{
                tree.tokenTag(parse_error.token).symbol(),
            });
        },

        .invalid_byte => {
            const tok_slice = tree.source[tree.tokens.items(.start)[parse_error.token]..];
            return w.print("{s} contains invalid byte: '{f}'", .{
                switch (tok_slice[0]) {
                    '\'' => "character literal",
                    '"', '\\' => "string literal",
                    '/' => "comment",
                    else => unreachable,
                },
                std.zig.fmtChar(tok_slice[parse_error.extra.offset]),
            });
        },

        .expected_token => {
            const found_tag = tree.tokenTag(parse_error.token);
            const expected_symbol = parse_error.extra.expected_tag.symbol();
            switch (found_tag) {
                .invalid => return w.print("expected '{s}', found invalid bytes", .{
                    expected_symbol,
                }),
                else => return w.print("expected '{s}', found '{s}'", .{
                    expected_symbol, found_tag.symbol(),
                }),
            }
        },
    }
}

pub const Error = struct {
    tag: Tag,
    is_note: bool = false,
    token: TokenIndex,
    extra: union {
        none: void,
        expected_tag: Token.Tag,
        offset: usize,
    } = .{ .none = {} },

    pub const Tag = enum {
        expected_expr,
        expected_noun,

        /// `expected_tag` is populated.
        expected_token,

        /// `offset` is populated.
        invalid_byte,
    };
};

/// Index into `extra_data`.
pub const ExtraIndex = enum(u32) {
    _,
};

pub const Node = struct {
    tag: Tag,
    main_token: TokenIndex,
    data: Data,

    /// Index into `nodes`.
    pub const Index = enum(u32) {
        root = 0,
        _,

        pub fn toOptional(i: Index) OptionalIndex {
            const result: OptionalIndex = @enumFromInt(@intFromEnum(i));
            assert(result != .none);
            return result;
        }

        pub fn toOffset(base: Index, destination: Index) Offset {
            const base_i64: i64 = @intFromEnum(base);
            const destination_i64: i64 = @intFromEnum(destination);
            return @enumFromInt(destination_i64 - base_i64);
        }
    };

    /// Index into `nodes`, or null.
    pub const OptionalIndex = enum(u32) {
        root = 0,
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(oi: OptionalIndex) ?Index {
            return if (oi == .none) null else @enumFromInt(@intFromEnum(oi));
        }

        pub fn fromOptional(oi: ?Index) OptionalIndex {
            return if (oi) |i| i.toOptional() else .none;
        }
    };

    /// A relative node index.
    pub const Offset = enum(i32) {
        zero = 0,
        _,

        pub fn toOptional(o: Offset) OptionalOffset {
            const result: OptionalOffset = @enumFromInt(@intFromEnum(o));
            assert(result != .none);
            return result;
        }

        pub fn toAbsolute(offset: Offset, base: Index) Index {
            return @enumFromInt(@as(i64, @intFromEnum(base)) + @intFromEnum(offset));
        }
    };

    /// A relative node index, or null.
    pub const OptionalOffset = enum(i32) {
        none = std.math.maxInt(i32),
        _,

        pub fn unwrap(oo: OptionalOffset) ?Offset {
            return if (oo == .none) null else @enumFromInt(@intFromEnum(oo));
        }
    };

    comptime {
        // Goal is to keep this under one byte for efficiency.
        assert(@sizeOf(Tag) == 1);

        if (!std.debug.runtime_safety) {
            assert(@sizeOf(Data) == 8);
        }
    }

    pub const Tag = enum {
        /// The root node which is guaranteed to be at `Node.Index.root`.
        ///
        /// The `main_token` field is the first token for the source file.
        root,
        /// The `data` field is unused.
        ///
        /// The `main_token` field is the previous token.
        empty,

        /// `(expr)`.
        ///
        /// The `data` field is a `.node_and_token`:
        ///   1. a `Node.Index` to the sub-expression.
        ///   2. a `TokenIndex` to the `)` token.
        ///
        /// The `main_token` field is the `(` token.
        grouped_expression,
        /// `()`.
        ///
        /// The `data` field is a `.token` of the `)`.
        ///
        /// The `main_token` field is the `(` token.
        empty_list,
        /// `(a;b;...)`.
        ///
        /// The `data` field is a `.extra_range` that stores a `Node.Index` for
        /// each element.
        ///
        /// The `main_token` field is the `(` token.
        list,
        /// `([]a;b;...)`.
        ///
        /// The `data` field is a `.extra_and_token`:
        ///   1. a `ExtraIndex` to a `Table`.
        ///   2. a `TokenIndex` to the `)` token.
        ///
        /// The `main_token` field is the `(` token.
        table_literal,

        /// `{[]expr}`.
        ///
        /// The `data` field is a `.extra_and_token`:
        ///   1. a `ExtraIndex` to a `Lambda`.
        ///   2. a `TokenIndex` to the `}` token.
        ///
        /// The `main_token` field is the `{` token.
        lambda,

        /// `[expr]`.
        ///
        /// The `data` field is a `.extra_range` that stores a `Node.Index` for
        /// each element.
        ///
        /// The `main_token` field is the `[` token.
        expr_block,

        /// `expr[a;b;...]`.
        ///
        /// The `data` field is a `.extra_range` that stores a `Node.Index` for
        /// each element.
        ///
        /// The `main_token` field is the `[` token.
        call,
        /// `expr expr`.
        ///
        /// The `data` field is a `.node_and_node`.
        ///
        /// The `main_token` field is unused.
        apply_unary,
        /// `expr op expr`.
        ///
        /// The `data` field is a `.node_and_opt_node`.
        ///
        /// The `main_token` field is the operator node.
        apply_binary,

        /// The `main_token` field is the `!` token.
        bang,
        /// The `main_token` field is the `#` token.
        hash,
        /// The `main_token` field is the `$` token.
        dollar,
        /// The `main_token` field is the `%` token.
        percent,
        /// The `main_token` field is the `&` token.
        ampersand,
        /// The `main_token` field is the `*` token.
        asterisk,
        /// The `main_token` field is the `+` token.
        plus,
        /// The `main_token` field is the `,` token.
        comma,
        /// The `main_token` field is the `-` token.
        minus,
        /// The `main_token` field is the `.` token.
        dot,
        /// The `main_token` field is the `:` token.
        colon,
        /// The `main_token` field is the `<` token.
        angle_bracket_left,
        /// The `main_token` field is the `=` token.
        equals,
        /// The `main_token` field is the `>` token.
        angle_bracket_right,
        /// The `main_token` field is the `?` token.
        question_mark,
        /// The `main_token` field is the `@` token.
        at,
        /// The `main_token` field is the `^` token.
        caret,
        /// The `main_token` field is the `_` token.
        underscore,
        /// The `main_token` field is the `|` token.
        pipe,
        /// The `main_token` field is the `~` token.
        tilde,

        /// The `main_token` field is the `!:` token.
        bang_colon,
        /// The `main_token` field is the `#:` token.
        hash_colon,
        /// The `main_token` field is the `$:` token.
        dollar_colon,
        /// The `main_token` field is the `%:` token.
        percent_colon,
        /// The `main_token` field is the `&:` token.
        ampersand_colon,
        /// The `main_token` field is the `*:` token.
        asterisk_colon,
        /// The `main_token` field is the `+:` token.
        plus_colon,
        /// The `main_token` field is the `,:` token.
        comma_colon,
        /// The `main_token` field is the `-:` token.
        minus_colon,
        /// The `main_token` field is the `.:` token.
        dot_colon,
        /// The `main_token` field is the `::` token.
        colon_colon,
        /// The `main_token` field is the `<:` token.
        angle_bracket_left_colon,
        /// The `main_token` field is the `=:` token.
        equals_colon,
        /// The `main_token` field is the `>:` token.
        angle_bracket_right_colon,
        /// The `main_token` field is the `?:` token.
        question_mark_colon,
        /// The `main_token` field is the `@:` token.
        at_colon,
        /// The `main_token` field is the `^:` token.
        caret_colon,
        /// The `main_token` field is the `_:` token.
        underscore_colon,
        /// The `main_token` field is the `|:` token.
        pipe_colon,
        /// The `main_token` field is the `~:` token.
        tilde_colon,

        /// `expr'`.
        ///
        /// The `data` field is a `.opt_node`.
        ///
        /// The `main_token` field is the `'` token.
        apostrophe,
        /// `expr':`.
        ///
        /// The `data` field is a `.opt_node`.
        ///
        /// The `main_token` field is the `':` token.
        apostrophe_colon,
        /// `expr/`.
        ///
        /// The `data` field is a `.opt_node`.
        ///
        /// The `main_token` field is the `/` token.
        slash,
        /// `expr/:`.
        ///
        /// The `data` field is a `.opt_node`.
        ///
        /// The `main_token` field is the `/:` token.
        slash_colon,
        /// `expr\`.
        ///
        /// The `data` field is a `.opt_node`.
        ///
        /// The `main_token` field is the `\` token.
        backslash,
        /// `expr\:`.
        ///
        /// The `data` field is a `.opt_node`.
        ///
        /// The `main_token` field is the `\:` token.
        backslash_colon,

        /// The `main_token` field is the number literal token.
        number_literal,
        /// `1 2 ...`.
        ///
        /// The `data` field is a `.token` that stores the last number literal token.
        ///
        /// The `main_token` field is the first number literal token.
        number_list_literal,
        /// The `main_token` field is the string literal token.
        string_literal,
        /// ```
        /// \\first line
        /// ...
        /// \\last line
        /// ```
        ///
        /// The `data` field is a `.token` that stores the last multiline string literal token.
        ///
        /// The `main_token` field is the first multiline string literal token.
        multiline_string_literal,
        /// The `main_token` field is the symbol literal token.
        symbol_literal,
        /// `` `a`b...``.
        ///
        /// The `data` field is a `.token` that stores the last symbol literal token.
        ///
        /// The `main_token` field is the first symbol literal token.
        symbol_list_literal,
        /// The `main_token` field is the identifier token.
        identifier,
    };

    pub const Data = union {
        node: Index,
        opt_node: OptionalIndex,
        token: TokenIndex,
        node_and_node: struct { Index, Index },
        node_and_opt_node: struct { Index, OptionalIndex },
        node_and_token: struct { Index, TokenIndex },
        opt_node_and_opt_node: struct { OptionalIndex, OptionalIndex },
        extra_and_token: struct { ExtraIndex, TokenIndex },
        extra_range: SubRange,
    };

    pub const SubRange = struct {
        /// Index into extra_data.
        start: ExtraIndex,
        /// Index into extra_data.
        end: ExtraIndex,
    };

    pub const Lambda = struct {
        params_start: ExtraIndex,
        body_start: ExtraIndex,
        body_end: ExtraIndex,
        trailing_semicolon: bool,
    };
};

fn testParse(source: [:0]const u8, expected: []const Node.Tag) !void {
    const gpa = std.testing.allocator;
    var tree: Ast = try .parse(gpa, source);

    defer tree.deinit(gpa);

    try std.testing.expect(tree.errors.len == 0);
    try std.testing.expectEqual(.root, tree.nodes.items(.tag)[0]);
    try std.testing.expectEqualSlices(Node.Tag, expected, tree.nodes.items(.tag)[1..]);
}

test {
    std.testing.refAllDecls(@This());
}

test "parse" {
    try testParse(
        \\\\test
        \\ \\ing
        \\ ,
        \\ \\test
        \\ \\ing
    , &.{ .multiline_string_literal, .apply_binary, .comma, .multiline_string_literal });
    try testParse(
        \\\\test
        \\\\ing
        \\ ,
        \\ \\test
        \\ \\ing
    , &.{
        .multiline_string_literal, .multiline_string_literal, .apply_binary, .comma, .multiline_string_literal,
    });
}
