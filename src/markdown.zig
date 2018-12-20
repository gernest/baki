const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const Buffer = std.Buffer;
const unicode = @import("zunicode");
const utf8 = unicode.utf8;

const form_feed = 0x0C;
const line_tabulation = 0x0B;
const space = ' ';

// UsizeMap is a map of string keys to usize values.
pub const UsizeMap = std.AutoHashMap([]const u8, usize);

/// Markdown provides facilities for parsing and rendering mardkwon documents.
/// This code was ported from go's blackfriday  available at http://github.com/russross/blackfriday
pub const Markdown = struct {
    /// markdown extensions supported by the parser.
    const Extension = struct {
        pub const NoIntraEmphasis: usize = 1;
        pub const Tables: usize = 2;
        pub const FencedCode: usize = 4;
        pub const Autolink: usize = 8;
        pub const Strikethrough: usize = 16;
        pub const LaxHtmlBlocks: usize = 32;
        pub const SpaceHeaders: usize = 64;
        pub const HardLineBreak: usize = 128;
        pub const TabSizeEight: usize = 256;
        pub const Footnotes: usize = 512;
        pub const NoEmptyLineBeforeBlock: usize = 1024;
        pub const HeaderIds: usize = 2048;
        pub const Titleblock: usize = 4096;
        pub const AutoHeaderIds: usize = 8192;
        pub const BackslashLineBreak: usize = 16384;
        pub const DefinitionLists: usize = 32768;
        pub const JoinLines: usize = 65536;
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

    // TableAlignment is html table alignment options
    pub const TableAlignment = enum {
        None,
        Left,
        Right,
        Center,
    };

    const Renderer = struct {
        blockCode: fn (r: *Renderer, out: *Buffer, text: []const u8, info_string: []const u8) anyerror!void,
        blockQuote: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        blockHtml: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        header: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter, level: usize, id: ?[]const u8) anyerror!void,
        hrule: fn (r: *Renderer, out: *Buffer) anyerror!void,
        list: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter, flags: usize) anyerror!void,
        listItem: fn (r: *Renderer, out: *Buffer, text: []const u8, flags: usize) anyerror!void,
        paragraph: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter) anyerror!void,
        table: fn (r: *Renderer, out: *Buffer, header: []const u8, body: []const u8, column_data: []usize) anyerror!void,
        tableRow: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        tableHeaderCell: fn (r: *Renderer, out: *Buffer, text: []const u8, alignment: TableAlignment) anyerror!void,
        tableCell: fn (r: *Renderer, out: *Buffer, text: []const u8, alignment: TableAlignment) anyerror!void,
        footNotes: fn (r: *Renderer, out: *Buffer, text_iter: *TextIter) anyerror!void,
        footNoteItem: fn (r: *Renderer, out: *Buffer, name: []const u8, text: []const u8, flags: usize) anyerror!void,
        titleBlock: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,

        //span level
        autoLink: fn (r: *Renderer, out: *Buffer, link: []const u8, kind: LinkType) anyerror!void,
        codeSpan: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        doubleEmphasis: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        emphasis: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        image: fn (r: *Renderer, out: *Buffer, link: []const u8, title: []const u8, alt: []const u8) anyerror!void,
        lineBreak: fn (r: *Renderer, out: *Buffer) anyerror!void,
        link: fn (r: *Renderer, out: *Buffer, link: []const u8, title: []const u8, content: []const u8) anyerror!void,
        rawHtmlTag: fn (r: *Renderer, out: *Buffer, tag: []const u8) anyerror!void,
        tripleEmphasis: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        strikethrough: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,
        footnoteRef: fn (r: *Renderer, out: *Buffer, ref: []const u8, id: usize) anyerror!void,

        entity: fn (r: *Renderer, out: *Buffer, entity: []const u8) anyerror!void,
        normalText: fn (r: *Renderer, out: *Buffer, text: []const u8) anyerror!void,

        documentHeader: fn (r: *Renderer, out: *Buffer) anyerror!void,
        documentFooter: fn (r: *Renderer, out: *Buffer) anyerror!void,

        flags: usize,
    };

    const TextIter = struct {
        next: fn (*TextIter) anyerror!void,

        fn text(self: *TextIter) bool {
            if (self.next(self)) {
                return true;
            } else |_| {
                // TODO handle OutOfMemory error here
                return false;
            }
        }
    };

    const Reference = struct {
        link: []const u8,
        title: []const u8,
        text: []const u8,
    };

    const RefOverid = struct {
        overideFn: fn (*RefOverid, ref: []const u8) *Reference,
    };

    const InlineParser = struct {
        parse: fn (self: *InlineParser, p: *Parser, out: *Buffer, data: []const u8, offset: usize) anyerror!usize,
    };

    // inline parsers
    emphasis: InlineParser,

    const BaseReference = struct {
        link: []const u8,
        title: []const u8,
        note_id: ?usize,
        hash_block: bool,
        text: []const u8,
    };

    const Parser = struct {
        render: *Renderer,
        refs: std.AutoHashMap([]const u8, *BaseReference),
        inline_callbacks: [256]?*InlineParser,
        flags: usize,
        nesting: usize,
        max_nesting: usize,
        inside_link: bool,
        allocator: *mem.Allocator,
        notes: std.ArrayList(*BaseReference),
        notes_record: std.AutoHashMap([]const u8, bool),

        // newBaseReference is ahelper for creating a *BaseReference object.
        fn newBaseReference(self: *Parser) anyerror!*BaseReference {
            return self.allocator.createOne(BaseReference);
        }

        fn deinit(self: *Parser) !void {
            const ref = &self.refs;
            var it = &ref.iterator();
            while (it.next()) |v| {
                self.destroy(v);
            }
            ref.deinit();
            self.notes.deinit();
            self.notes_record.deinit();
        }

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

        fn block(self: *Parser, out: *Buffer, data: []const u8) !void {
            if (data.len == 0 or data[data.len - 1] != '\n') {
                return error.MissingTerminalNewLine;
            }
            if (self.nesting >= self.max_nesting) {
                return;
            }
            self.nesting += 1;
            var i: usize = 0;
            while (i < data.len) {
                // prefixed header:
                //
                // # Header 1
                // ## Header 2
                // ...
                // ###### Header 6
                if (self.isPrefixHeader(data[i..])) {}
            }
        }

        fn isPrefixHeader(self: *Parser, data: []const u8) bool {
            if (data[0] != '#') {
                return false;
            }
            if (self.flags & Extension.SpaceHeaders != 0) {
                var level: usize = 0;
                while (level < 6 and data[level] == '#') {
                    level += 1;
                }
                if (data[level] != ' ') {
                    return false;
                }
            }
            return true;
        }

        fn prefixHeader(self: *Parser, data: []const u8) usize {
            var level: usize = 0;
            while (level < 6 and data[level] == '#') {
                level += 1;
            }
            const i = Util.skipChar(data, level, ' ');
            var end = Util.skipUntilChar(data, i, '\n');
            var skip = end;
            var id: []const u8 = "";
            if (self.flags & Extension.HeaderIds != 0) {
                var j = i;
                var k: usize = 0;
                // find start/end of header id
                while (j < end - 1 and (data[j] != '{' or data[j + 1] != '#')) : (i += 1) {}
                k = j + 1;
                while (k < end and data[k] != '}') : (k += 1) {}
                // extract header id if found
                if (j < end and k < end) {
                    id = data[j + 1 .. k];
                    end = j;
                    skip = k + 1;
                    while (end > 0 and data[end - 1] == ' ') {
                        end -= 1;
                    }
                }
            }
            while (end > 0 and data[end - 1] == '#') {
                if (Util.isBackslashEscaped(data[i..], end - 1)) {
                    break;
                }
                end -= 1;
            }
            while (end > 0 and data[end - 1] == ' ') {
                end -= 1;
            }
        }
    };

    fn emphasisFn(inline_parse: *InlineParser, p: *Parser, out: *Buffer, data: []const u8, offset: usize) void {
        const self = @fieldParentPtr(Markdown, "emphasis", inline_parse);
        self.parseEmphasis(p, out, data, offset);
    }

    fn parseEmphasis(self: *Markdown, p: *Parser, out: *Buffer, data: []const u8, offset: usize) usize {
        var ctx = data[offset..];
        const c = ctx[0];
        if (ctx.len > 2 and ctx[1] != c) {
            // whitespace cannot follow an opening emphasis;
            // strikethrough only takes two characters '~~'
            if (c == '~' and Util.isSpace(ctx[1])) {
                return 0;
            }
        }
    }

    const Options = struct {
        extensions: usize,
        ref_overid: ?*RefOverid,
    };
};

// Util are utility/helper functions.
const Util = struct {
    ///  writes to buffer bytes s with occurance of old replaced with new. n is
    /// the max number of replacements if n<0 then there is no limit to the
    /// number of replcacement.
    fn replace(out: *Buffer, s: []const u8, old: []const u8, new: []const u8, n: isize) !void {
        var i: usize = 0;
        var replacement: isize = 0;
        if (n < 0) {
            replacement = @intCast(isize, s.len);
        }
        while (i < s.len and n < replacement) {
            if (mem.indexOf(u8, s[i..], old)) |idx| {
                try out.append(s[i .. idx + i]);
                try out.append(new);
                i += idx + old.len;
                replacement += 1;
            } else {
                try out.append(s[i..]);
                return;
            }
        }
    }

    fn map(out: *Buffer, mapping: fn (r: i32) i32, src: []const u8) !void {
        var max_bytes = src.len;
        try out.resize(max_bytes);
        var nb_bytes: usize = 0;
        var i: usize = 0;
        while (i < src.len) {
            var wid: usize = 1;
            var r = @intCast(i32, src[i]);
            if (r >= utf8.rune_self) {
                const rune = try utf8.decodeRune(src[i..]);
                wid = rune.size;
                r = rune.value;
            }
            r = mapping(r);
            if (r >= 0) {
                const rune_length = try utf8.runeLen(r);
                if (nb_bytes + rune_length > max_bytes) {
                    max_bytes = max_bytes * 2 + utf8.utf_max;
                    try out.resize(max_bytes);
                }
                const w = try utf8.encodeRune(out.toSlice()[nb_bytes..max_bytes], r);
                nb_bytes += w;
            }
            i += wid;
        }
        try out.resize(nb_bytes);
    }

    fn toUpper(buf: *Buffer, s: []const u8) !void {
        return map(buf, unicode.toUpper, s);
    }

    fn toLower(buf: *Buffer, s: []const u8) !void {
        return map(buf, unicode.toLower, s);
    }

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

    fn findEmphChar(data: []const u8, c: u8) ?usize {
        var i: usize = 0;
        while (i < data.len) {
            while (i < data.len and data[i] != c and data[i] != '`' and data[i] != '[') : (i += 1) {}
            if (i >= data.len) {
                return null;
            }
            // do not count escaped chars
            if (i != 0 and data[i - 1] == '\\') {
                i += 1;
                continue;
            }
            if (data[i] == c) {
                return i;
            }
            if (data[i] == '`') {
                // skip a code span
                var tmp: usize = 0;
                i += 1;
                while (i < data.len and data[i] != '`') {
                    if (tmp == 0 and data[i] == c) {
                        tmp = i;
                    }
                    i += 1;
                }
                if (i >= data.len) {
                    return tmp;
                }
                i += 1;
            } else if (data[i] == '[') {
                // skip a link
                var tmp: usize = 0;
                i += 1;
                while (i < data.len and data[i] != ']') {
                    if (tmp == 0 and data[i] == c) {
                        tmp = i;
                    }
                    i += 1;
                }
                i += 1;
                while (i < data.len and (data[i] == ' ' or data[i] == '\n')) {
                    i += 1;
                }
                if (i >= data.len) {
                    return tmp;
                }
                if (data[i] != '[' and data[i] != '(') { // not a link
                    if (tmp > 0) {
                        return tmp;
                    }
                    continue;
                }
                const cc = data[i];
                i += 1;
                while (i < data.len and data[i] != cc) {
                    if (tmp == 0 and data[i] == c) {
                        return i;
                    }
                    i += 1;
                }
            }
        }
        return null;
    }

    fn emphasis(p: *Markdown.Parser, out: *Buffer, data: []const u8, c: u8) !?usize {
        var i: usize = 0;
        // skip one symbol if coming from emph3
        if (data.len > 1 and data[0] == c and data[1] == c) {
            i = 1;
        }
        var buf = &try Buffer.init(p.allocator, "");
        defer buf.deinit();

        while (i < data.len) {
            const length = findEmphChar(ctx[i..], c);
            if (length == 0) {
                return 0;
            }
            i += length;
            if (i >= data.len) {
                return 0;
            }
            if (i + 1 < data.len and data[i + 1] == c) {
                i += 1;
                continue;
            }
            if (data[i] == c and !Util.isSpace(data[i - 1])) {
                if ((p.flags & Extension.NoIntraEmphasis) != 0) {
                    if (i + 1 == data.len or isSpace(data[i + 1]) or isPunct(data[i + 1])) {
                        continue;
                    }
                }
                try buf.resize(0);
                try p.inlineBlock(buf, data[0..i]);
                try p.renderer.emphasis(out, buf.toSlice());
                return i + 1;
            }
        }
        return null;
    }

    fn doubleEmphasis(p: *Markdown.Parser, out: *Buffer, data: []const u8, c: u8) !?usize {
        var i: usize = 0;
        var buf = &try Buffer.init(p.allocator, "");
        defer buf.deinit();
        while (i < data.len) {
            if (findEmphChar(data[i..], c)) |length| {
                i += length;
                if (i + 1 < data.len and data[i] == c and data[i + 1] == c and i > 0 and !isSpace(datai - 1)) {
                    try buf.resize(0);
                    try p.inlineBlock(buf, data[0..i]);
                    if (buf.len() > 0) {
                        // pick the right renderer
                        if (c == '~') {
                            try p.renderer.strikethrough(out, buf.toSlice());
                        } else {
                            try p.renderer.doubleEmphasis(out, buf.toSlice());
                        }
                    }
                    return i + 2;
                }
            }
            break;
        }
        return null;
    }

    fn tripleEmphasis(p: *Markdown.Parser, out: *Buffer, data: []const u8, offset: usize, c: u8) !?usize {
        var i: usize = 0;
        const ctx = data[offset..];
        var buf = &try Buffer.init(p.allocator, "");
        defer buf.deinit();
        while (i < ctx.len) {
            if (findEmphChar(ctx[i..], c)) |length| {
                i += length;
                // skip whitespace preceded symbols
                if (ctx[i] != c or isSpace(ctx[i - 1])) {
                    continue;
                }
                if (i + 2 < ctx.len and ctx[i + 1] == c and ctx[i + 2] == c) {
                    try buf.resize(0);
                    try p.inlineBlock(buf, ctx[0..i]);
                    if (buf.len() > 0) {
                        try p.renderer.tripleEmphasis(out, buf.toSlice());
                    }
                    return i + 3;
                } else if (i + 1 < ctx.len & &ctx[i + 1] == c) {
                    // double symbol found, hand over to emph1
                    const e = try emphasis(p, out, data[offset - 2 ..], c);
                    if (e) |length| {
                        return length - 2;
                    }
                    return null;
                }
                const e = try doubleEmphasis(p, out, data[offset - 1], c);
                if (e) |length| {
                    return length - 1;
                }
                return null;
            }
            return null;
        }
        return null;
    }

    fn doubleSpace(out: *Buffer) !void {
        if (out.len() > 0) {
            try out.appendByte('\n');
        }
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

    fn slugify(out: *Buffer, in: []const u8) !void {
        const a = out.len();
        var sym = false;
        for (in) |c| {
            if (isalnum(c)) {
                sym = false;
                try out.appendByte(c);
            } else if (sym) {
                continue;
            } else {
                try out.appendByte('-');
                sym = true;
            }
        }
        //TODO: think more about this and correctly implement it.
    }
};

test "Util.map" {
    var a = std.debug.global_allocator;
    var buf = &try Buffer.init(a, "");
    defer buf.deinit();
    try Util.toUpper(buf, "mamaMia");
    assert(buf.eql("MAMAMIA"));

    try Util.toLower(buf, "mamaMia");
    assert(buf.eql("mamamia"));
}

test "Util.replace" {
    var a = std.debug.global_allocator;
    var buf = &try Buffer.init(a, "");
    defer buf.deinit();
    try Util.replace(buf, "mamaMia ameenda na mimi", "m", "x", -1);
    assert(buf.eql("xaxaMia axeenda na xixi"));
}

// HTML implements the Markdown.Renderer interafce for html documents.
const HTML = struct {
    allocator: *mem.Allocator,
    flags: usize,
    close_tag: []const u8,
    title: ?[]const u8,
    css: ?[]const u8,
    toc_marker: usize,
    header_count: usize,
    current_level: usize,
    toc: Buffer,
    header_ids: UsizeMap,
    params: ?Params,
    renderer: Markdown.Renderer,

    pub const VERSION = "1.5";

    // Params options for configuring HTML renderer.
    const Params = struct {
        /// prepend this to each relative url.
        abs_prefix: ?[]const u8,

        ///This will be added to  each footnote text.
        footnote_anchor_prefix: ?[]const u8,

        /// Show this text inside the <a> tag for a footnote return link, if the
        /// HTML_FOOTNOTE_RETURN_LINKS flag is enabled. If blank, the string
        /// <sup>[return]</sup> is used.
        footnote_return_link_contents: ?[]const u8,

        /// If set, add this text to the front of each Header ID, to ensure
        /// uniqueness.
        header_id_prefix: ?[]const u8,

        /// If set, add this text to the back of each Header ID, to ensure
        /// uniqueness.
        header_id_suffix: ?[]const u8,
    };

    /// Flags options that controls the HTML output
    pub const Flags = struct {
        pub const SkipHtml: usize = 1; // skip preformatted HTML blocks
        pub const SkipStyle: usize = 2; // skip embedded <style> elements
        pub const SkipImages: usize = 4; // skip embedded images
        pub const SkipLinks: usize = 8; // skip all links
        pub const Safelink: usize = 16; // only link to trusted protocols}
        pub const NofollowLinks: usize = 32; // only link with re:usizel="nofollow"
        pub const NoreferrerLinks: usize = 64; // only link with re:usizel="noreferrer"
        pub const HrefTargetBlank: usize = 128; // add a blank target
        pub const Toc: usize = 256; // generate a table of contents
        pub const OmitContents: usize = 512; // skip the main contents (for a standalone table of contents)
        pub const CompletePage: usize = 1024; // generate a complete HTML page
        pub const UseXhtml: usize = 2048; // generate XHTML output instead of HTML
        pub const UseSmartypants: usize = 4096; // enable smart punctuation substitutions
        pub const SmartypantsFractions: usize = 8192; // enable smart fractions (with HTML_USE_SMARTYPANTS)
        pub const SmartypantsDashes: usize = 16384; // enable smart dashes (with HTML_USE_SMARTYPANTS)
        pub const SmartypantsLatexDashes: usize = 32768; // enable LaTeX-style dashes (with HTML_USE_SMARTYPANTS and HTML_SMARTYPANTS_DASHES)
        pub const SmartypantsAngledQuotes: usize = 65536; // enable angled double quotes (with HTML_USE_SMARTYPANTS) for double quotes rendering
        pub const SmartypantsQuotesNbsp: usize = 131072; // enable "French guillemets" (with HTML_USE_SMARTYPANTS)
        pub const FootnoteReturnLinks: usize = 262144; // generate a link at the end of a footnote to return to the source
    };

    const TableAlignment = Markdown.TableAlignment;
    const Renderer = Markdown.Renderer;
    const TextIter = Markdown.TextIter;
    const LinkType = Markdown.LinkType;
    pub const html_close = ">";

    pub fn init(a: *mem.Allocator, flags: usize) !HTML {
        return HTML{
            .allocator = a,
            .flags = flags,
            .close_tag = html_close,
            .title = null,
            .css = null,
            .toc_marker = 0,
            .header_count = 0,
            .current_level = 0,
            .toc = try Buffer.init(a, ""),
            .header_ids = UsizeMap.init(a),
            .params = null,
            .renderer = Renderer{
                .blockCode = blockCode,
                .blockQuote = blockQuote,
                .blockHtml = blockHtml,
                .header = header,
                .hrule = hrule,
                .list = list,
                .listItem = listItem,
                .paragraph = paragraph,
                .table = table,
                .tableRow = tableRow,
                .tableHeaderCell = tableHeaderCell,
                .tableCell = tableCell,
                .footNotes = footNotes,
                .footNoteItem = footNoteItem,
                .titleBlock = titleBlock,
                .autoLink = autoLink,
                .codeSpan = codeSpan,
                .doubleEmphasis = doubleEmphasis,
                .emphasis = emphasis,
                .image = image,
                .lineBreak = lineBreak,
                .link = link,
                .rawHtmlTag = rawHtmlTag,
                .tripleEmphasis = tripleEmphasis,
                .strikethrough = strikethrough,
                .footnoteRef = footnoteRef,
                .entity = entity,
                .normalText = normalText,
                .documentHeader = documentHeader,
                .documentFooter = documentFooter,
                .flags = 0,
            },
        };
    }

    pub fn blockCode(r: *Renderer, out: *Buffer, text: []const u8, info_string: []const u8) anyerror!void {}

    pub fn blockQuote(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try Util.doubleSpace(out);
        try out.append("<blockquote>\n");
        try out.append(text);
        try out.append("</blockquote>\n");
    }

    pub fn blockHtml(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        const html = @fieldParentPtr(HTML, "renderer", r);
        if (html.hasFlag(Flags.SkipHtml)) {
            return;
        }
        try Util.doubleSpace(out);
        try out.append(text);
        try out.appendByte('\n');
    }

    pub fn header(r: *Renderer, out: *Buffer, text_iter: *TextIter, level: usize, id: ?[]const u8) anyerror!void {}

    pub fn hrule(r: *Renderer, out: *Buffer) anyerror!void {
        const html = @fieldParentPtr(HTML, "renderer", r);
        try Util.doubleSpace(out);
        try out.append("<hr");
        try out.append(html.close_tag);
        try out.appendByte('\n');
    }

    pub fn list(r: *Renderer, out: *Buffer, text_iter: *TextIter, flags: usize) anyerror!void {}
    pub fn listItem(r: *Renderer, out: *Buffer, text: []const u8, flags: usize) anyerror!void {}

    pub fn paragraph(r: *Renderer, out: *Buffer, text_iter: *TextIter) anyerror!void {
        const mark = out.len();
        try Util.doubleSpace(out);
        try out.append("<p>");
        if (!text_iter.text()) {
            try out.resize(mark);
            return;
        }
        try out.append("</p>\n");
    }

    pub fn table(r: *Renderer, out: *Buffer, header_text: []const u8, body: []const u8, column_data: []usize) anyerror!void {
        try Util.doubleSpace(out);
        try out.append("<table>\n<thead>\n");
        try out.append(header_text);
        try out.append("</thead>\n\n<tbody>\n");
        try out.append(body);
        try out.append("</tbody>\n</table>\n");
    }

    pub fn tableRow(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try Util.doubleSpace(out);
        try out.append("<tr>\n");
        try out.append(text);
        try out.append("\n</tr>\n");
    }

    pub fn tableHeaderCell(r: *Renderer, out: *Buffer, text: []const u8, alignment: TableAlignment) anyerror!void {
        try Util.doubleSpace(out);
        switch (alignment) {
            TableAlignment.Left => {
                try out.append("<th align=\"left\">");
            },
            TableAlignment.Right => {
                try out.append("<th align=\"right\">");
            },
            TableAlignment.Center => {
                try out.append("<th align=\"center\">");
            },
            TableAlignment.None => {
                try out.append("<th>");
            },
            else => unreachable,
        }
        try out.append(text);
        try out.append("</th>");
    }

    pub fn tableCell(r: *Renderer, out: *Buffer, text: []const u8, alignment: TableAlignment) anyerror!void {
        try Util.doubleSpace(out);
        switch (alignment) {
            TableAlignment.Left => {
                try out.append("<tdalign=\"left\">");
            },
            TableAlignment.Right => {
                try out.append("<td align=\"right\">");
            },
            TableAlignment.Center => {
                try out.append("<td align=\"center\">");
            },
            TableAlignment.None => {
                try out.append("<td>");
            },
            else => unreachable,
        }
        try out.append(text);
        try out.append("</td>");
    }

    pub fn footNotes(r: *Renderer, out: *Buffer, text_iter: *TextIter) anyerror!void {}
    pub fn footNoteItem(r: *Renderer, out: *Buffer, name: []const u8, text: []const u8, flags: usize) anyerror!void {}

    pub fn titleBlock(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        const html = @fieldParentPtr(HTML, "renderer", r);
        var buf = &try Buffer.init(html.allocator, "");
        defer buf.deinit();
        const txt = Util.trimPrefix(text, "% ");
        try Util.replace(buf, txt, "\n% ", "\n", -1);
        try out.append("<h1 class=\"title\">");
        try out.append(buf.toSlice());
        try out.append("\n</h1>");
    }

    pub fn autoLink(r: *Renderer, out: *Buffer, link_text: []const u8, kind: LinkType) anyerror!void {}
    pub fn codeSpan(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try out.append("<code>");
        try attrEscape(out, text);
        try out.append("</code>");
    }
    pub fn doubleEmphasis(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try out.append("<strong>");
        try out.append(text);
        try out.append("</strong>");
    }
    pub fn emphasis(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        if (text.len == 0) {
            return;
        }
        try out.append("<em>");
        try out.append(text);
        try out.append("</em>");
    }
    pub fn image(r: *Renderer, out: *Buffer, link_text: []const u8, title: []const u8, alt: []const u8) anyerror!void {}
    pub fn lineBreak(r: *Renderer, out: *Buffer) anyerror!void {}
    pub fn link(r: *Renderer, out: *Buffer, link_text: []const u8, title: []const u8, content: []const u8) anyerror!void {}
    pub fn rawHtmlTag(r: *Renderer, out: *Buffer, tag: []const u8) anyerror!void {}
    pub fn tripleEmphasis(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try out.append("<del>");
        try out.append(text);
        try out.append("</del>");
    }
    pub fn strikethrough(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try out.append("<strong><em>");
        try out.append(text);
        try out.append("</em></strong>");
    }

    pub fn footnoteRef(r: *Renderer, out: *Buffer, ref: []const u8, id: usize) anyerror!void {
        const html = @fieldParentPtr(HTML, "renderer", r);
        try out.append("<sup class=\"footnote-ref\" id=\"");
        try out.append("fnref:");
        if (html.params) |params| {
            if (params.footnote_anchor_prefix) |v| {
                try out.append(v);
            }
        }
        try Util.slugify(out, ref);
        try out.append("\"><a href=\"#");
        try out.append("fn:");
        if (html.params) |params| {
            if (params.footnote_anchor_prefix) |v| {
                try out.append(v);
            }
        }
        try Util.slugify(out, ref);
        try out.append("\">");
        var stream = &std.BufferOutStream.init(out).stream;
        try stream.print("{}", id);
    }

    pub fn entity(r: *Renderer, out: *Buffer, entity_text: []const u8) anyerror!void {
        try out.append(entity_text);
    }

    pub fn normalText(r: *Renderer, out: *Buffer, text: []const u8) anyerror!void {
        try attrEscape(out, text);
    }

    pub fn documentHeader(r: *Renderer, out: *Buffer) anyerror!void {
        var html = @fieldParentPtr(HTML, "renderer", r);
        if (!html.hasFlag(Flags.CompletePage)) {
            return;
        }
        var ending: u8 = 0;
        if (html.hasFlag(Flags.UseXhtml)) {
            try out.append("<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" ");
            try out.append("\"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n");
            try out.append("<html xmlns=\"http://www.w3.org/1999/xhtml\">\n");
            ending = '/';
        } else {
            try out.append("<!DOCTYPE html>\n");
            try out.append("<html>\n");
        }
        try out.append("<head>\n");
        try out.append("  <title>");
        if (html.title) |v| {
            try out.append(v);
        }
        try out.append("</title>\n");
        try out.append("  <meta name=\"GENERATOR\" content=\"Blackfriday Markdown Processor v");
        try out.append(VERSION);
        try out.append("\"");
        if (ending != 0) {
            try out.appendByte(ending);
        }
        try out.append(">\n");
        try out.append("  <meta charset=\"utf-8\"");
        if (ending != 0) {
            try out.appendByte(ending);
        }
        try out.append(">\n");
        if (html.css) |css| {
            try out.append("  <link rel=\"stylesheet\" type=\"text/css\" href=\"");
            try attrEscape(out, css);
            try out.append("\"");
            if (ending != 0) {
                try out.appendByte(ending);
            }
            try out.append(">\n");
        }
        try out.append("</head>\n");
        try out.append("<body>\n");
        html.toc_marker = out.len();
    }

    pub fn hasFlag(self: *HTML, f: usize) bool {
        return (self.flags & f) != 0;
    }

    pub fn ensureUniqueHeaderID(self: *HTML, buf: *Buffer, id: []const u8) !void {
        var stream = &BufferOutStream.init(buf).stream;
        var m = &self.HeaderIds;
        const kv = try m.get(id);
        if (kv != null) {
            const count = kv.?.value + 1;
            try stream.print("{}-{}", id, count);
            _ = try m.put(buf.toSlice(), count);
            return;
        }
        const count = 0;
        try stream.print("{}-{}", id, count);
        _ = try m.put(buf.toSlice(), count);
        return;
    }

    pub fn documentFooter(r: *Renderer, out: *Buffer) anyerror!void {}

    const escape_quote = "&quot;";
    const escape_and = "&amp;";
    const escape_less = "&lt;";
    const escape_greater = "&gt;";
    const escape_nothing = "";
    fn escapeSingleChar(c: u8) []const u8 {
        return switch (c) {
            '"' => escape_quote,
            '&' => escape_and,
            '<' => escape_less,
            '>' => escape_greater,
            else => escape_nothing,
        };
    }

    fn attrEscape(out: *Buffer, src: []const u8) !void {
        var org: usize = 0;
        for (src) |ch, idx| {
            const e = escapeSingleChar(ch);
            if (e.len > 0) {
                if (idx > org) {
                    // copy all the normal characters since the last escape
                    try out.append(src[org..idx]);
                }
                org += idx + 1;
                try out.append(e);
            }
        }
        if (org < src.len) {
            try out.append(src[org..]);
        }
    }
};

test "HTML" {
    var h = try HTML.init(std.debug.global_allocator, 0);
}