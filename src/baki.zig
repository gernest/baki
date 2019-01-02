const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode = std.unicode;
const warn = std.debug.warn;
const mem = std.mem;

const form_feed = 0x0C;
const line_tabulation = 0x0B;
const space = ' ';

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

    const IterLine = struct {
        src: []const u8,
        current_pos: usize,

        // this says when to stop looking for a next new line. When null the end
        // of input will be used instead.
        limit: ?usize,

        fn init(src: []const u8, current_pos: usize, limit: ?usize) IterLine {
            return IterLine{
                .src = src,
                .current_pos = current_pos,
                .limit = limit,
            };
        }

        fn next(self: *IterLine) ?Position {
            if (self.limit != null and self.current_pos >= self.limit.?) {
                return null;
            }
            var limit: usize = self.src.len;
            if (self.limit) |v| {
                limit = v;
            }
            if (Util.index(self.src[self.current_pos..], "\n")) |idx| {
                if (self.current_pos + idx > limit) {
                    // We employ limit here as relative to where the last line
                    // might be.
                    //
                    // This case here the limiting index is inside the text that
                    // ends with a new line so we disqualify the whole line. To
                    // ensure that we wont waste time for next calls we progress
                    // the cursor so no further checks will be performed.
                    self.current_pos += idx;
                    return null;
                }
                const c = self.current_pos;
                // we are including the new line character as we want to
                // preserve originality.
                self.current_pos += idx + 1;
                return Position{
                    .begin = c,
                    .end = self.current_pos,
                };
            }
            if (limit <= self.src.len) {
                // yield the rest of the input;
                const c = self.current_pos;
                self.current_pos = self.src.len;
                return Position{
                    .begin = c,
                    .end = self.current_pos,
                };
            }
            return null;
        }
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

    // findSetextHeading checks if in is begins with a setext heading. Returns
    // the offset of the heading relative to the beginning of the in where the
    // setext block ends.
    //
    // The offset includes the - or == sequence line up to its line ending.
    fn findSetextHeading(in: []const u8) ?usize {
        if (in.len == 0) {
            return null;
        }
        if (findSetextSequence(in)) |idx| {
            var count_new_lines: usize = 0;
            var last_line_index: usize = 0;
            var i: usize = 0;
            while (i < idx) : (i += 1) {
                const c = in[i];
                if (c == '\n') {
                    count_new_lines += 1;

                    // all lines must have not more than 3 space indentation and
                    // should. contain at least one non whitespace character.
                    var j: usize = last_line_index;
                    const indent_size = Util.indentation(in[j..]);
                    if (indent_size > 3) {
                        return null;
                    }
                    var valid = false;
                    while (j < i) {
                        if (!Util.isSpace(in[j])) {
                            valid = true;
                            break;
                        }
                    }
                    if (!valid) {
                        return null;
                    }
                    last_line_index = i;
                }
                i += 1;
            }
            if (count_new_lines == 0) {
                // We save the trouble of keeping going because a setext must be
                // in one or more lines folowwed by the setext line sequence.
                return null;
            }
            warn("new lines:{}\n", count_new_lines);

            // quicly verify the setext sequence is correct before further
            // checks. This should begin with not more than 3 character space
            // indent followwed by 2 or more setext sequence and any number of
            // white stapec.
        }
        return null;
    }

    fn findSetextSequence(in: []const u8) ?usize {
        if (Util.index(in, "==")) |idx| {
            return idx;
        }
        return Util.index(in, "--");
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

    fn indentation(data: []const u8) usize {
        if (data.len == 0) {
            return 0;
        }
        if (data[0] == '\t') {
            return 1;
        }

        var i: usize = 0;
        var idx: usize = 0;
        while (i < data.len) : (i += 1) {
            if (data[i] != ' ') {
                break;
            }
            idx += 1;
        }
        return idx;
    }

    /// returns true if sub_slice is within s.
    pub fn contains(s: []const u8, sub_slice: []const u8) bool {
        return mem.indexOf(u8, s, sub_slice) != null;
    }

    pub fn index(s: []const u8, sub_slice: []const u8) ?usize {
        return mem.indexOf(u8, s, sub_slice);
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

const suite = @import("test_suite.zig");
test "Lexer" {
    var lx = &Lexer.init(std.debug.global_allocator);
    defer lx.deinit();
    try lx.run();
}

test "Lexer.findSetextHeading" {
    const TestCase = struct {
        const Self = @This();
        in: []const u8,
        offset: ?usize,
        fn init(in: []const u8, offset: ?usize) Self {
            return Self{ .in = in, .offset = offset };
        }
    };
    const new_case = TestCase.init;

    const cases = []TestCase{
        new_case(
            \\Foo *bar*
            \\=========
        , null),
        // The content of the header may span more than one line
        new_case(
            \\Foo *bar
            \\baz*
            \\====
        , null),
        new_case(
            \\Foo *bar
            \\baz*
            \\====
        , null),
        // The underlining can be any length:
        new_case(
            \\Foo
            \\-------------------------
        , null),
        new_case(
            \\Foo
            \\=
        , null),
        // The heading content can be indented up to three spaces, and need not
        // line up with the underlining.
        new_case(
            \\   Foo
            \\---
        , null),
        new_case(
            \\  Foo
            \\-----
        , null),
        new_case(
            \\  Foo
            \\  ===
        , null),
        // Four spaces indent is too much.
        new_case(
            \\    Foo
            \\    ---
        , null),
        new_case(
            \\    Foo
            \\---
        , null),
        // The setext heading underline can be indented up to three spaces, and
        // may have trailing spaces.
        new_case(
            \\Foo
            \\   ----      
        , null),
    };

    for (cases) |case| {
        // const idx = Lexer.findSetextHeading(case.in);
        // warn(":  index {}\n", idx);
    }
}

test "IterLine" {
    const TestCase = struct {
        const Self = @This();
        in: []const u8,
        start_pos: usize,
        limit: ?usize,
        begin: usize,
        end: usize,
        fn init(in: []const u8, start_pos: usize, limit: ?usize, begin: usize, end: usize) Self {
            return Self{
                .in = in,
                .start_pos = start_pos,
                .limit = limit,
                .begin = begin,
                .end = end,
            };
        }
    };
    const new_case = TestCase.init;
    const cases = []TestCase{
        // plain line
        new_case("abc", 0, null, 0, 3),
        // ,ust include the new line character
        new_case("abc\ndef", 0, null, 0, 4),
        new_case("abc\ndef", 5, 6, 5, 7),
    };
    for (cases) |case| {
        var iter = &Lexer.IterLine.init(case.in, case.start_pos, case.limit);
        if (iter.next()) |pos| {
            const expect_pos = Lexer.Position{ .begin = case.begin, .end = case.end };
            if (pos.begin != expect_pos.begin or pos.end != expect_pos.end) {
                warn("case : {} expected position {} got {}\n", case, expect_pos, pos);
                return error.WrongPosition;
            }
        } else {
            if (!(case.begin == 0 and case.end == 0)) {
                const pos = Lexer.Position{ .begin = case.begin, .end = case.end };
                warn("case: {} expcedted position:{} got null\n", case, pos);
                return error.PositionMustNotBeNull;
            }
        }
    }
}
