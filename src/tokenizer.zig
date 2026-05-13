const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{});

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        l_paren,
        r_paren,
        l_bracket,
        r_bracket,
        l_brace,
        r_brace,
        semicolon,

        bang,
        hash,
        dollar,
        percent,
        ampersand,
        asterisk,
        plus,
        comma,
        minus,
        dot,
        colon,
        angle_bracket_left,
        equals,
        angle_bracket_right,
        question_mark,
        at,
        caret,
        underscore,
        pipe,
        tilde,

        bang_colon,
        hash_colon,
        dollar_colon,
        percent_colon,
        ampersand_colon,
        asterisk_colon,
        plus_colon,
        comma_colon,
        minus_colon,
        dot_colon,
        colon_colon,
        angle_bracket_left_colon,
        equals_colon,
        angle_bracket_right_colon,
        question_mark_colon,
        at_colon,
        caret_colon,
        underscore_colon,
        pipe_colon,
        tilde_colon,

        apostrophe,
        slash,
        backslash,
        apostrophe_colon,
        slash_colon,
        backslash_colon,

        identifier,
        number_literal,
        string_literal,
        multiline_string_literal,
        symbol_literal,

        invalid,
        eos,
        eof,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .l_paren => "(",
                .r_paren => ")",
                .l_bracket => "[",
                .r_bracket => "]",
                .l_brace => "{",
                .r_brace => "}",
                .semicolon => ";",

                .bang => "!",
                .hash => "#",
                .dollar => "$",
                .percent => "%",
                .ampersand => "&",
                .asterisk => "*",
                .plus => "+",
                .comma => ",",
                .minus => "-",
                .dot => ".",
                .colon => ":",
                .angle_bracket_left => "<",
                .equals => "=",
                .angle_bracket_right => ">",
                .question_mark => "?",
                .at => "@",
                .caret => "^",
                .underscore => "_",
                .pipe => "|",
                .tilde => "~",

                .bang_colon => "!:",
                .hash_colon => "#:",
                .dollar_colon => "$:",
                .percent_colon => "%:",
                .ampersand_colon => "&:",
                .asterisk_colon => "*:",
                .plus_colon => "+:",
                .comma_colon => ",:",
                .minus_colon => "-:",
                .dot_colon => ".:",
                .colon_colon => "::",
                .angle_bracket_left_colon => "<:",
                .equals_colon => "=:",
                .angle_bracket_right_colon => ">:",
                .question_mark_colon => "?:",
                .at_colon => "@:",
                .caret_colon => "^:",
                .underscore_colon => "_:",
                .pipe_colon => "|:",
                .tilde_colon => "~:",

                .apostrophe => "'",
                .slash => "/",
                .backslash => "\\",
                .apostrophe_colon => "':",
                .slash_colon => "/:",
                .backslash_colon => "\\:",

                .identifier,
                .number_literal,
                .string_literal,
                .multiline_string_literal,
                .symbol_literal,
                => null,

                .invalid,
                .eos,
                .eof,
                => null,
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .identifier => "an identifier",
                .number_literal => "a number literal",
                .string_literal => "a string literal",
                .multiline_string_literal => "a multiline string literal",
                .symbol_literal => "a symbol literal",
                .invalid => "invalid token",
                .eos => "end of statement",
                .eof => "EOF",
                else => unreachable,
            };
        }
    };

    pub fn eof(index: usize) Token {
        return .{
            .tag = .eof,
            .loc = .{
                .start = index,
                .end = index,
            },
        };
    }
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,
    prev_tag: Token.Tag = .semicolon, // default to a tag which begins a new expression.

    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present.
        var tokenizer: Tokenizer = .{
            .buffer = buffer,
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
        };
        tokenizer.skip();
        return tokenizer;
    }

    const SkipState = enum {
        start,
        skip_line,
    };

    fn skip(self: *Tokenizer) void {
        state: switch (SkipState.start) {
            .start => switch (self.buffer[self.index]) {
                0 => if (self.index != self.buffer.len) continue :state .skip_line,
                '\n' => {
                    self.index += 1;
                    continue :state .start;
                },
                ' ', '\t', '\r' => continue :state .skip_line,
                '/' => switch (self.buffer[self.index + 1]) {
                    '/' => continue :state .skip_line,
                    else => {},
                },
                else => {},
            },

            .skip_line => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index != self.buffer.len) continue :state .skip_line,
                    '\n' => {
                        self.index += 1;
                        continue :state .start;
                    },
                    else => continue :state .skip_line,
                }
            },
        }
    }

    const State = enum {
        start,
        string_literal,
        string_literal_backslash,
        multiline_string_literal,
        identifier,
        number_literal,
        symbol_literal,
        bang,
        hash,
        dollar,
        percent,
        ampersand,
        apostrophe,
        asterisk,
        plus,
        comma,
        negative,
        minus,
        dot,
        slash,
        colon,
        angle_bracket_left,
        equals,
        angle_bracket_right,
        question_mark,
        at,
        backslash,
        caret,
        underscore,
        pipe,
        tilde,
        skip_colon,
        skip_line,
        newline,
        invalid,
    };

    pub fn next(self: *Tokenizer) Token {
        var result: Token = .{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => if (self.index != self.buffer.len) {
                    continue :state .invalid;
                } else return .eof(self.buffer.len),
                '\n' => continue :state .newline,
                ' ', '\t', '\r' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                'a'...'z', 'A'...'Z' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '"' => {
                    result.tag = .string_literal;
                    continue :state .string_literal;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    continue :state .number_literal;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                },
                '[' => {
                    result.tag = .l_bracket;
                    self.index += 1;
                },
                ']' => {
                    result.tag = .r_bracket;
                    self.index += 1;
                },
                '`' => {
                    result.tag = .symbol_literal;
                    continue :state .symbol_literal;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                },
                '!' => continue :state .bang,
                '#' => continue :state .hash,
                '$' => continue :state .dollar,
                '%' => continue :state .percent,
                '&' => continue :state .ampersand,
                '\'' => continue :state .apostrophe,
                '*' => continue :state .asterisk,
                '+' => continue :state .plus,
                ',' => continue :state .comma,
                '-' => {
                    if (self.index == 0) continue :state .negative;
                    switch (self.buffer[self.index - 1]) {
                        ' ', '\t', '\n' => continue :state .negative,
                        else => switch (self.prev_tag) {
                            .r_paren,
                            .r_bracket,
                            .r_brace,

                            .identifier,
                            .number_literal,
                            .string_literal,
                            .multiline_string_literal,
                            .symbol_literal,
                            => continue :state .minus,

                            else => continue :state .negative,
                        },
                    }
                },
                '.' => continue :state .dot,
                '/' => continue :state .slash,
                ':' => continue :state .colon,
                '<' => continue :state .angle_bracket_left,
                '=' => continue :state .equals,
                '>' => continue :state .angle_bracket_right,
                '?' => continue :state .question_mark,
                '@' => continue :state .at,
                '\\' => continue :state .backslash,
                '^' => continue :state .caret,
                '_' => continue :state .underscore,
                '|' => continue :state .pipe,
                '~' => continue :state .tilde,
                else => continue :state .invalid,
            },

            .string_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        result.tag = .invalid;
                    } else continue :state .invalid,
                    '\n' => result.tag = .invalid,
                    '\\' => continue :state .string_literal_backslash,
                    '"' => self.index += 1,
                    0x01...0x08, 0x0b...0x1f, 0x7f => continue :state .invalid,
                    else => continue :state .string_literal,
                }
            },
            .string_literal_backslash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '"', '\\', 'n', 'r', 't' => continue :state .string_literal,
                    else => continue :state .invalid,
                }
            },

            .multiline_string_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => {},
                    '\r' => if (self.buffer[self.index + 1] != '\n') continue :state .invalid,
                    0x01...0x08, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                    else => continue :state .multiline_string_literal,
                }
            },

            .identifier => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9' => continue :state .identifier,
                    else => {
                        const ident = self.buffer[result.loc.start..self.index];
                        if (Token.getKeyword(ident)) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },

            .number_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9', '.' => continue :state .number_literal,
                    else => {},
                }
            },

            .symbol_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9', '.' => continue :state .symbol_literal,
                    else => {},
                }
            },

            .bang => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .bang_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .bang,
                }
            },
            .hash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .hash_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .hash,
                }
            },
            .dollar => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .dollar_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .dollar,
                }
            },
            .percent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .percent_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .percent,
                }
            },
            .ampersand => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .ampersand_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .ampersand,
                }
            },
            .apostrophe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .bang_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .bang,
                }
            },
            .asterisk => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .asterisk_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .asterisk,
                }
            },
            .plus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .plus_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .plus,
                }
            },
            .comma => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .comma_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .comma,
                }
            },
            .negative => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .minus_colon;
                        continue :state .skip_colon;
                    },
                    '0'...'9' => {
                        result.tag = .number_literal;
                        continue :state .number_literal;
                    },
                    else => result.tag = .minus,
                }
            },
            .minus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .minus_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .minus,
                }
            },
            .dot => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .dot_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .dot,
                }
            },
            .slash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '/' => continue :state .skip_line,
                    ':' => {
                        result.tag = .slash_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .slash,
                }
            },
            .colon => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .colon_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .colon,
                }
            },
            .angle_bracket_left => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .angle_bracket_left_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .angle_bracket_left,
                }
            },
            .equals => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .equals_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .equals,
                }
            },
            .angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .angle_bracket_right_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .angle_bracket_right,
                }
            },
            .question_mark => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .question_mark_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .question_mark,
                }
            },
            .at => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .at_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .at,
                }
            },
            .backslash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '\\' => {
                        result.tag = .multiline_string_literal;
                        continue :state .multiline_string_literal;
                    },
                    ':' => {
                        result.tag = .backslash_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .backslash,
                }
            },
            .caret => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .caret_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .caret,
                }
            },
            .underscore => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .underscore_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .underscore,
                }
            },
            .pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .pipe_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .pipe,
                }
            },
            .tilde => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .tilde_colon;
                        continue :state .skip_colon;
                    },
                    else => result.tag = .tilde,
                }
            },
            .skip_colon => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => continue :state .skip_colon,
                    else => {},
                }
            },

            .skip_line => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index != self.buffer.len) {
                        continue :state .invalid;
                    } else return .eof(self.buffer.len),
                    '\n' => continue :state .newline,
                    else => continue :state .skip_line,
                }
            },

            .newline => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index != self.buffer.len) {
                        continue :state .invalid;
                    } else return .eof(self.buffer.len),
                    '\n' => continue :state .newline,
                    ' ', '\t', '\r' => {
                        self.index += 1;
                        result.loc.start = self.index;
                        continue :state .start;
                    },
                    '/' => switch (self.buffer[self.index + 1]) {
                        '/' => continue :state .skip_line,
                        else => result.tag = .eos,
                    },
                    else => result.tag = .eos,
                }
            },

            .invalid => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        result.tag = .invalid;
                    } else continue :state .invalid,
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },
        }

        result.loc.end = self.index;
        return result;
    }
};

fn testTokenize(source: [:0]const u8, expected: []const Token.Tag) !void {
    const gpa = std.testing.allocator;

    var tokenizer: Tokenizer = .init(source);
    var tokens: std.MultiArrayList(Token) = .empty;
    defer tokens.deinit(gpa);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, token);
        if (token.tag == .eof) break;
    }

    const tags = tokens.items(.tag);
    try std.testing.expectEqual(.eof, tags[tags.len - 1]);
    try std.testing.expectEqualSlices(Token.Tag, expected, tags[0 .. tags.len - 1]);
}

test {
    std.testing.refAllDecls(@This());
}

test "tokenize" {
    try testTokenize(
        \\\\test
        \\\\ing
        \\ ,
        \\ \\test
        \\ \\ing
        \\ ;
    , &.{
        .multiline_string_literal, .eos,                      .multiline_string_literal, .comma,
        .multiline_string_literal, .multiline_string_literal, .semicolon,
    });
    try testTokenize(
        \\\\test
        \\ \\ing
        \\ ,
        \\ \\test
        \\ \\ing
        \\ ;
    , &.{
        .multiline_string_literal, .multiline_string_literal, .comma,
        .multiline_string_literal, .multiline_string_literal, .semicolon,
    });
    try testTokenize(
        \\0
        \\// comment
        \\ 1
    , &.{ .number_literal, .number_literal });
    try testTokenize(
        \\0
        \\// comment
        \\1
    , &.{ .number_literal, .eos, .number_literal });
    try testTokenize(
        \\ 0
        \\1
        \\ 2
    , &.{ .number_literal, .number_literal });
    try testTokenize(
        \\ 0
        \\// comment
        \\1
        \\ 2
    , &.{ .number_literal, .number_literal });
    try testTokenize(
        \\ 0
        \\// comment
        \\ 1
        \\2
    , &.{.number_literal});
    try testTokenize(
        \\ 0
        \\// comment
        \\ 1
        \\ 2
    , &.{});
}
