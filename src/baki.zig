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

    fn next(self: *Lexer) !?u32 {
        if (lself.current_pos >= self.input.len) {
            return null;
        }
        const c = try unicode.utf8Decode(self.input[self.current_pos..]);
        const width = try unicode.utf8CodepointSequenceLength(c);
        self.width = @intCast(usize, width);
        self.current_pos += self.width;
        return c;
    }

    fn run(self: *Lexer) void {
        self.state = lex_any;
        while (self.state) |state| {
            self.state = state.lex(self);
        }
    }

    const lexState = struct {
        lexFn: fn (lx: *lexState, lexer: *Lexer) ?*lexState,

        fn lex(self: *lexState, lx: *Lexer) ?*lexState {
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
            CodeBlock,
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

    const AnyLexer = struct {
        state: lexState,
        fn init() AnyLexer {
            return AnyLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) ?*lexState {
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
        fn lexFn(self: *lexState, lx: *Lexer) ?*lexState {}
    };

    const HorizontalRuleLexer = struct {
        state: lexState,
        fn init() HeadingLexer {
            return HorizontalRuleLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) ?*lexState {}
    };

    const CodeBlockLexer = struct {
        state: lexState,
        fn init() HeadingLexer {
            return CodeBlockLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) ?*lexState {}
    };

    const TextLexer = struct {
        state: lexState,
        fn init() HeadingLexer {
            return TextLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) ?*lexState {}
    };

    const HTMLLexer = struct {
        state: lexState,
        fn init() HeadingLexer {
            return HTMLLexer{
                .state = lexState{ .lexFn = lexFn },
            };
        }
        fn lexFn(self: *lexState, lx: *Lexer) ?*lexState {}
    };
};

const suite = @import("test_suite.zig");
test "Lexer" {
    var lx = &Lexer.init(std.debug.global_allocator);
    lx.run();
}
