const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode = std.unicode;

const Lexer = struct {
    input: []const u8,
    state: ?*lexState,

    /// This is the current position in the input stream.
    current_pos: usize,

    /// start_pos index on the current token starting point in the input stream
    start_pos: usize,

    width: usize,

    /// position of the last emitted token.
    last_pos: ?Position,

    lexme_list: LexMeList,
    allocator: *Allocator,

    fn init(allocator: *Allocator) Lexer {
        var lx: Lexer = undefined;
        lx.allocator = allocator;
        lx.lexme_list = LexMeList.init(allocator);
        return lx;
    }

    fn deinit(self: *Lexer) void {
        self.lexme_list.deinit();
    }

    fn next(self: *Lexer) !?u32 {
        if (self.current_pos >= self.input.len) {
            return null;
        }
        const c = try unicode.utf8Decode(self.input[self.current_pos..]);
        const width = try unicode.utf8CodepointSequenceLength(c);
        self.width = @intCast(usize, width);
        self.current_pos += self.width;
        return c;
    }

    fn backup(self: *Lexer) void {
        self.current_pos -= self.width;
    }

    fn peek(self: *Lexer) !?u32 {
        const r = try self.next();
        self.backup();
        return r;
    }

    fn run(self: *Lexer) !void {
        self.state = lex_any;
        while (self.state) |state| {
            self.state = try state.lex(self);
        }
    }

    const lexState = struct {
        lexFn: fn (lx: *lexState, lexer: *Lexer) anyerror!?*lexState,

        fn lex(self: *lexState, lx: *Lexer) !?*lexState {
            return self.lexFn(self, lx);
        }
    };

    const LexMeList = std.ArrayList(LexMe);

    const LexMe = struct {
        id: Id,
        pos: Position,
        const Id = enum {
            EOF,
            NewLine,
            HTML,
            Heading,
            BlockQuote,
            List,
            ListItem,
            FencedCodeBlock,
            Hr, // horizontal rule
            Table,
            LpTable,
            TableRow,
            TableCell,
            Strong,
            Italic,
            Strike,
            Code,
            Link,
            DefLink,
            RefLink,
            AutoLink,
            Image,
            RefImage,
            Text,
            Br,
            Pipe,
            Indent,
        };
    };

    const Position = struct {
        begin: usize,
        end: usize,
    };

    fn emit(self: *Lexer, id: LexMe.Id) !void {
        var a = &self.lexme_list;
        try a.append(LexMe{
            .id = id,
            .pos = Position{
                .begin = self.start,
                .end = self.current_pos,
            },
        });
        self.start = self.current_pos;
    }

    const lex_any = &AnyLexer.init().state;
    const lex_heading = &HeadingLexer.init().state;
    const lex_horizontal_rule = &HorizontalRuleLexer.init().state;
    const lex_code_block = &CodeBlockLexer.init().state;
    const lex_text = &TextLexer.init().state;
    const lex_html = &HTMLLexer.init().state;
    const lex_list = &ListLexer.init().state;
    const lex_block_quote = &BlockQuoteLexer.init().state;
    const lex_def_link = &DefLinkLexer.init().state;
    const lex_fenced_code_block = &FencedCodeBlockLexer.init().state;

    const AnyLexer = struct {
        state: lexState,
        fn init() AnyLexer {
            return AnyLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }

        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            while (try lx.peek()) |r| {
                switch (r) {
                    '*', '-', '_' => {
                        return lex_horizontal_rule;
                    },
                    '+', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                        return lex_list;
                    },
                    '<' => {
                        return lex_html;
                    },
                    '>' => {
                        return lex_block_quote;
                    },
                    '[' => {
                        return lex_def_link;
                    },
                    '`', '~' => {
                        return lex_fenced_code_block;
                    },
                    '#' => {
                        return lex_heading;
                    },
                    else => {},
                }
            }
            return null;
        }
    };

    const HeadingLexer = struct {
        state: lexState,
        fn init() HeadingLexer {
            return HeadingLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const HorizontalRuleLexer = struct {
        state: lexState,
        fn init() HorizontalRuleLexer {
            return HorizontalRuleLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const CodeBlockLexer = struct {
        state: lexState,
        fn init() CodeBlockLexer {
            return CodeBlockLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const TextLexer = struct {
        state: lexState,

        fn init() TextLexer {
            return TextLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }

        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            while (try lx.peek()) |r| {
                switch (r) {
                    '\n' => {
                        if (ls.current_pos > ls.start_pos and Util.hasPrefix(lx.input[lx.current_pos + 1 ..], "    ")) {
                            _ = try lx.next();
                            continue;
                        }
                        if (lx.current_pos > ls.start_pos) {
                            try lx.emit(LexMe.Text);
                        }
                        lx.pos += lx.width;
                        try lx.emit(LexMe.NewLine);
                        break;
                    },
                    else => {},
                }
            }
            return lex_any;
        }
    };

    const HTMLLexer = struct {
        state: lexState,
        fn init() HTMLLexer {
            return HTMLLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const ListLexer = struct {
        state: lexState,
        fn init() ListLexer {
            return ListLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const BlockQuoteLexer = struct {
        state: lexState,
        fn init() BlockQuoteLexer {
            return BlockQuoteLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const DefLinkLexer = struct {
        state: lexState,
        fn init() DefLinkLexer {
            return DefLinkLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };

    const FencedCodeBlockLexer = struct {
        state: lexState,
        fn init() FencedCodeBlockLexer {
            return FencedCodeBlockLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) !?*lexState {
            return error.TODO;
        }
    };
};

const suite = @import("test_suite.zig");
test "Lexer" {
    var lx = &Lexer.init(std.debug.global_allocator);
    defer lx.deinit();
    try lx.run();
}

// Util are utility/helper functions.
const Util = struct {
    const punct_marks = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    fn isPunct(c: u8) bool {
        for (punct_marks) |char| {
            if (c == char) {
                return true;
            }
        }
        return false;
    }

    /// returns true if c is a whitespace character.
    fn isSpace(c: u8) bool {
        return isHorizontalSpace(c) or isVersicalSpace(c);
    }

    fn isBackslashEscaped(data: []const u8, i: usize) bool {
        var bs: usize = 0;
        while ((@intCast(isize, i) - @intCast(isize, bs) - 1) >= 0 and data[i - bs - 1] == '\\') {
            bs += 1;
        }
        return bs == 1;
    }

    fn isHorizontalSpace(c: u8) bool {
        return c == ' ' or c == '\t';
    }

    fn isVersicalSpace(c: u8) bool {
        return c == '\n' or c == '\r' or c == form_feed or c == line_tabulation;
    }

    fn isLetter(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }

    fn isalnum(c: u8) bool {
        return (c >= '0' and c <= '9') or isLetter(c);
    }

    // Find if a line counts as indented or not.
    // Returns number of characters the indent is (0 = not indented).
    fn isIndented(data: []const u8, indent_size: usize) usize {
        if (data.len == 0) {
            return 0;
        }
        if (data[0] == '\t') {
            return 1;
        }
        if (data.len < indent_size) {
            return 0;
        }
        var i: usize = 0;
        while (i < indent_size) : (i += 1) {
            if (data[i] != space) {
                return 0;
            }
        }
        return indent_size;
    }

    /// returns true if sub_slice is within s.
    pub fn contains(s: []const u8, sub_slice: []const u8) bool {
        return mem.indexOf(u8, s, sub_slice) != null;
    }

    /// hasPrefix returns true if slice s begins with prefix.
    pub fn hasPrefix(s: []const u8, prefix: []const u8) bool {
        return s.len >= prefix.len and
            equal(s[0..prefix.len], prefix);
    }

    pub fn hasSuffix(s: []const u8, suffix: []const u8) bool {
        return s.len >= suffix.len and
            equal(s[s.len - suffix.len ..], suffix);
    }

    pub fn trimPrefix(s: []const u8, prefix: []const u8) []const u8 {
        return mem.trimLeft(u8, s, prefix);
    }

    pub fn trimSuffix(s: []const u8, suffix: []const u8) []const u8 {
        return mem.trimRight(u8, s, suffix);
    }

    fn skipUntilChar(text: []const u8, start: usize, c: usize) usize {
        var i = start;
        while (i < tag.len and text[i] != c) : (i += 1) {}
        return i;
    }

    fn skipSpace(tag: []const u8, i: usize) usize {
        while (i < tag.len and isSpace(tag[i])) : (i += 1) {}
        return i;
    }

    fn skipChar(data: []const u8, start: usize, c: u8) usize {
        var i = start;
        while (i < data.len and data[i] == c) : (i += 1) {}
        return i;
    }

    fn isRelativeLink(link: []const u8) bool {
        if (link[0] == '#') {
            return true;
        }
        if (link.len >= 2 and link[0] == '/' and link[1] != '/') {
            return true;
        }
        // current directory : begin with "./"
        if (hasPrefix(link, "./")) {
            return true;
        }
        // parent directory : begin with "../"
        if (hasPrefix(link, "../")) {
            return true;
        }
        return false;
    }
};