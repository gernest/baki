const std = @import("std");
const mem = std.mem;
const Buffer = std.Buffer;
const unicode = @import("zunicode");
const utf8 = unicode.utf8;

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
};
