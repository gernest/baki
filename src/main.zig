const std = @import("std");

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
        HashTag, // #
        Escape, // #
    };

    // lex braks down src into smaller tokens. This interprets src as unicode
    // code points.
    fn lex(self: *Markdown, src: []const u8) !void {}
};
