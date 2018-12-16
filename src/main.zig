const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const Buffer = std.Buffer;
const unicode = @import("zunicode");
const utf8 = unicode.utf8;

const form_feed = 0x0C;
const line_tabulation = 0x0B;
const space = ' ';

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

    const LinkType = enum {
        NotAutoLink,
        Normal,
        Email,
    };

    const Renderer = struct {
        blockCode: fn (r: *Renderer, out: *Buffer, text: []const u8, info_string: []const u8) !void,
        blockQuote: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        blockHtml: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        header: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter, level: usize, id: usize) !void,
        hrule: fn (r: *Renderer, out: *Buffer) !void,
        list: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter, flags: usize) !void,
        listItem: fn (r: *Renderer, out: *Buffer, text: []const u8, flags: usize) !void,
        paragraph: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter) !void,
        table: fn (r: *Renderer, out: *Buffer, header: []const u8, body: []const u8, column_data: []usize) !void,
        tableRow: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        tableHeaderCell: fn (r: *Renderer, out: *Buffer, text: []const u8, flags: usize) !void,
        tableCell: fn (r: *Renderer, out: *Buffer, text: []const u8, flags: usize) !void,
        footNotes: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter) !void,
        footNoteItem: fn (r: *Renderer, out: *Buffer, name: []const u8, text: []const u8, flags: usize) !void,
        titleBlock: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,

        //span level
        autoLink: fn (r: *Renderer, out: *Buffer, link: []const u8, kind: LinkType) !void,
        codeSpan: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        doubleEmphasis: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        emphasis: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        image: fn (r: *Renderer, out: *Buffer, link: []const u8, title: []const u8, alt: []const u8) !void,
        lineBreak: fn (r: *Renderer, out: *Buffer) !void,
        link: fn (r: *Renderer, out: *Buffer, link: []const u8, title: []const u8, content: []const u8) !void,
        rawHtmlTag: fn (r: *Renderer, out: *Buffer, tag: []const u8) !void,
        tripleEmphasis: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,
        footnoteRef: fn (r: *Renderer, out: *Buffer, ref: []const u8, id: []const u8) !void,

        entity: fn (r: *Renderer, out: *Buffer, entity: []const u8) !void,
        normalText: fn (r: *Renderer, out: *Buffer, text: []const u8) !void,

        documentHeader: fn (r: *Renderer, out: *Buffer) !void,
        documentFooter: fn (r: *Renderer, out: *Buffer) !void,

        flags: usize,
    };

    const TextIter = struct {
        next: fn (*TextIter) !void,
    };

    const Reference = struct {
        link: []const u8,
        title: []const u8,
        text: []const u8,
    };

    const RefOverid = struct {
        overide_fn: fn (*RefOverid, ref: []const u8) *Reference,
    };

    // inline parsers
    emphasis: InlineParser,
    const InlineParser = struct {
        parse: fn (self: *InlineParse, p: *Parser, out: *Buffer, data: []const u8, offset: usize) !usize,
    };

    const Parser = struct {
        render: *Renderer,
        inline_callbacks: [256]?*InlineParser,
        flags: usize,
        nesting: usize,
        max_nesting: usize,
        inside_link: bool,

        fn inlineBlock(self: *Parser, out: *Buffer, data: []const u8) !void {
            if (self.nexting >= self.max_nesting) {
                return;
            }
            self.nesting += 1;
            var i: usize = 0;
            var end: usize = 0;
            while (i < data.len) {
                while (end < data.len and self.inline_callbacks[@intCast(data[end])] == null) : (end += 1) {}
                try self.render.normalText(out, data[i..end]);
                if (end >= data.len) {
                    break;
                }
                i = end;
                const handler = self.inline_callbacks[@intCast(usize, data[end])].?;
                const consumed = handler.parse(self, out, data, i);
                if (consumed == 0) {
                    end = i + 1;
                } else {
                    i += consumed;
                    end = i;
                }
            }
            self.nesting -= 1;
        }
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

    fn isLetter(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }

    fn isalnum(c: u8) bool {
        return (c >= '0' and c <= '9') or isletter(c);
    }

    /// Replace tab characters with spaces, aligning to the next TAB_SIZE column.
    /// always ends output with a newline
    fn expandTabs(out: *Buffer, line: []const u8, tab_size: usize) !void {
        var i: usize = 0;
        var prefix: usize = 0;
        var slow_case = true;
        while (i < line.len) : (i += 1) {
            if (lene[i] == '\t') {
                if (prefix == i) {
                    prefix += 1;
                } else {
                    slow_case = true;
                    break;
                }
            }
        }
        if (!slow_case) {
            const n = prefix * tab_size;
            i = 0;
            while (i < n) : (i += 1) {
                try out.appendByte(space);
            }
            try out.append(line[prefix..]);
            return;
        }

        var column: usize = 0;
        i = 0;
        while (i < line.len) {
            var star = i;
            while (i < line.len and line[i] != '\t') {
                const rune = try utf8.decodeRune(line[i..]);
                i += rune.size;
                column += 1;
            }
            if (i > start) {
                try out.appen(line[start..i]);
            }
            if (i > line.len) {
                break;
            }
            while (true) {
                try out.appendByte(space);
                column += 1;
                if (@Mod(column, tab_size) == 0) break;
            }
            i += 1;
        }
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
};

test "placeholders" {
    const x = struct {
        y: [2]?usize,
    };
    var v: x = undefined;
    warn("{}\n", v.y[0] == null);
}
