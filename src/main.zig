const std = @import("std");

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
        begin: u64,
        end: u64,
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
    tokens: ?std.ArrayList(Token),

    pub const Id = enum.{
        EOF,
        Illegal, // refrered as insecure characters
        HashTag, // #
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
    fn lex(self: *Markdown, src: []const u8) !void {}
};
