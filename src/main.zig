const std = @import("std");
const mem = std.mem;
const utf8 = @import("./zunicode/src/utf8/index.zig");

const space: i32 = 0x20;
const tab: i32 = 0x09;
const new_line: i32 = 0x0A;
const carriage_return: i32 = 0x0D;
const line_tabulation: i32 = 0x0B;
const form_feed: i32 = 0x0C;

pub const Markdown = struct.{
    ///Token stores details about the markdown token.
    pub const Token = struct.{
        id: Id,
        begin: usize,
        end: usize,
        line: usize,
    };

    pub const Item = struct.{
        token: Token,
        kind: ItemKind,
    };

    /// ItemKind defines possible kinds of structures that can be represented by
    /// a markdown document.
    pub const ItemKind = enum.{
        Block,
        Inline,
    };

    /// is a list of collected tokens. This is null if parse hasn't been called
    /// yet.
    tokens: ?ToeknList,
    allocator: *mem.Allocator,

    pub const ToeknList = std.ArrayList(Token);

    pub const Id = enum.{
        EOF,
        Illegal, // refrered as insecure characters
        Space,
        Tab,
        NewLine,
        CarriageReturn,
        LineTabulation,
        FormFeed,
        Ident,
    };

    // lex braks down src into smaller tokens. This interprets src as unicode
    // code points.
    fn lex(self: *Markdown, src: []const u8) !void {
        var iterator = utf8.Iterator.init(src);
        if (self.tokens != null) {
            // just clear the prefious tokens
            self.tokens.?.resize(0);
        } else {
            self.tokens = ToeknList.init(self.allocator);
        }

        var last_pos: usize = 0;
        while (true) {
            var token: Token = undefined;
            token.begin = last_pos;
            const rune = try iterator.next();
            if (rune == null) {
                token.id = Id.EOF;
                self.tokens.?.append(token);
                break;
            }
            token.end = last_pos + rune.size;
            switch (rune.value) {
                0x00 => token.id = Id.Illegal,
                space => token.id = Id.Space,
                tab => token.id = Id.Tab,
                new_line => token.id = Id.NewLine,
                carriage_return => token.id = Id.CarriageReturn,
                line_tabulation => token.id = Id.LineTabulation,
                form_feed => token.id = Id.FormFeed,
                else => unreachable,
            }
            self.tokens.?.append(token);
        }
    }
};
