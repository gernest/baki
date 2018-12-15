const std = @import("std");
const mem = std.mem;
const Buffer = std.Buffer;
const unicode = @import("zunicode");
const utf8 = unicode.utf8;

const form_feed = 0x0C;
const line_tabulation = 0x0B;

/// Markdown provides facilities for parsing and rendering mardkwon documents.
/// This code was ported from go's blackfriday  available at http://github.com/russross/blackfriday
pub const Markdown = struct {
    /// markdown extensions supported by the parser.
    const Extension = enum(usize) {
        NoIntraEmphasis = 1,
        Tables = 2,
        FencedCode = 4,
        Autolink = 8,
        Strikethrough = 16,
        LaxHtmlBlocks = 32,
        SpaceHeaders = 64,
        HardLineBreak = 128,
        TabSizeEight = 256,
        Footnotes = 512,
        NoEmptyLineBeforeBlock = 1024,
        HeaderIds = 2048,
        Titleblock = 4096,
        AutoHeaderIds = 8192,
        BackslashLineBreak = 16384,
        DefinitionLists = 32768,
        JoinLines = 65536,
    };

    const common_extensions: usize = 0 |
        Extension.NoIntraEmphasis |
        Extension.Tables |
        Extension.FencedCode |
        Extension.Autolink |
        Extension.Strikethrough |
        Extension.SpaceHeaders |
        Extension.HeaderIds |
        Extension.BackslashLineBreak |
        Extension.DefinitionLists;

    const Context = struct {
        out: *Buffer,
        text: ?[]const u8,
        flags: ?usize,
        header: ?[]const u8,
        body: ?[]const u8,
        column_data: ?[]const u8,
        name: ?[]const u8,
        link: ?[]const u8,
        title: ?[]const u8,
        content: ?[]const u8,
        tag: ?[]const u8,
        ref: ?[]const u8,
        id: ?[]const u8,
        entity: ?[]const u8,
        pub fn hasText(self: *Context) bool {}
    };

    const Renderer = struct {
        blockCode: fn (r: *Renderer, ctx: *Context) void,
        block: fn (r: *Renderer, ctx: *Context) void,
    };

    const Reference = struct {
        link: []const u8,
        title: []const u8,
        text: []const u8,
    };

    const RefOverid = struct {
        overide_fn: fn (*RefOverid, ref: []const u8) *Reference,
    };

    const Parser = struct {
        r: *Renderer,
    };

    // inline parsers
    emphasis: InlineParser,
    const InlineParser = struct {
        parse_fn: fn (self: *InlineParse, p: *Parser, out: *Buffer, data: []const u8, offset: usize) void,
    };

    fn emphasisFn(
        inline_parse: *InlineParser,
        p: *Parser,
        out: *Buffer,
        data: []const u8,
        offset: usize,
    ) void {
        const self = @fieldParentPtr(Markdown, "emphasis", inline_parse);
        self.parseEmphasis(p, out, data, offset);
    }

    fn parseEmphasis(
        self: *Markdown,
        p: *Parser,
        out: *Buffer,
        data: []const u8,
        offset: usize,
    ) void {}

    const Options = struct {
        extensions: usize,
        ref_overid: ?*RefOverid,
    };

    pub fn render(
        input: []const u8,
        renderer: *Renderer,
    ) void {}
};

// Util are utility/helper functions.
const Util = struct {
    /// returns true if c is a whitespace character.
    fn isSpace(c: u8) bool {
        return isHorizontalSpace(c) or isVersicalSpace(c);
    }

    fn isHorizontalSpace(c: u8) bool {
        return c == ' ' or c == '\t';
    }

    fn isVersicalSpace(c: u8) bool {
        return c == '\n' or c == '\r' or c == form_feed or c == line_tabulation;
    }
};
