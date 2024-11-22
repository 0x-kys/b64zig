const std = @import("std");

const B64 = struct {
    table: []const u8,
    decode_table: [256]i8,

    pub fn init() B64 {
        const encode_table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        var decode_table = [_]i8{-1} ** 256;

        for (encode_table, 0..) |c, i| {
            decode_table[c] = @intCast(i);
        }

        return B64{
            .table = encode_table,
            .decode_table = decode_table,
        };
    }

    pub fn encode(self: B64, input: []const u8, allocator: std.mem.Allocator) ![]u8 {
        if (input.len == 0) return &[_]u8{};

        const output_len = (((input.len + 2) / 3) * 4);
        var output = try allocator.alloc(u8, output_len);

        var i: usize = 0;
        var j: usize = 0;

        while (i + 2 < input.len) : (i += 3) {
            const b1 = input[i];
            const b2 = input[i + 1];
            const b3 = input[i + 2];

            output[j] = self.table[(b1 >> 2) & 0x3F];
            output[j + 1] = self.table[((b1 & 0x03) << 4) | ((b2 >> 4) & 0x0F)];
            output[j + 2] = self.table[((b2 & 0x0F) << 2) | ((b3 >> 6) & 0x03)];
            output[j + 3] = self.table[b3 & 0x3F];

            j += 4;
        }

        const remaining = input.len - i;
        if (remaining == 1) {
            const b1 = input[i];
            output[j] = self.table[(b1 >> 2) & 0x3F];
            output[j + 1] = self.table[(b1 & 0x03) << 4];
            output[j + 2] = '=';
            output[j + 3] = '=';
        } else if (remaining == 2) {
            const b1 = input[i];
            const b2 = input[i + 1];
            output[j] = self.table[(b1 >> 2) & 0x3F];
            output[j + 1] = self.table[((b1 & 0x03) << 4) | ((b2 >> 4) & 0x0F)];
            output[j + 2] = self.table[(b2 & 0x0F) << 2];
            output[j + 3] = '=';
        }

        return output;
    }

    pub fn decode(self: B64, input: []const u8, allocator: std.mem.Allocator) ![]u8 {
        if (input.len == 0) return &[_]u8{};
        if (input.len % 4 != 0) return error.InvalidLength;

        var output_len = (input.len / 4) * 3;

        if (input.len > 0 and input[input.len - 1] == '=') {
            output_len -= 1;
            if (input.len > 1 and input[input.len - 2] == '=') {
                output_len -= 1;
            }
        }

        var output = try allocator.alloc(u8, output_len);
        var i: usize = 0;
        var j: usize = 0;

        while (i < input.len) {
            const c1 = self.decode_table[input[i]];
            const c2 = self.decode_table[input[i + 1]];
            const c3 = if (input[i + 2] == '=') -1 else self.decode_table[input[i + 2]];
            const c4 = if (input[i + 3] == '=') -1 else self.decode_table[input[i + 3]];

            if (c1 < 0 or c2 < 0 or (c3 < 0 and input[i + 2] != '=') or
                (c4 < 0 and input[i + 3] != '='))
            {
                allocator.free(output);
                return error.InvalidCharacter;
            }

            const v1: u8 = @intCast((c1 << 2) | (c2 >> 4));
            output[j] = v1;

            if (c3 >= 0) {
                const v2: u8 = @intCast(((c2 & 0x0F) << 4) | (c3 >> 2));
                output[j + 1] = v2;

                if (c4 >= 0) {
                    const v3: u8 = @intCast(((c3 & 0x03) << 6) | c4);
                    output[j + 2] = v3;
                }
            }

            i += 4;
            j += if (c4 >= 0) 3 else if (c3 >= 0) 2 else 1;
        }

        return output;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const b64 = B64.init();

    const original = "Hello, World!";
    const encoded = try b64.encode(original, allocator);
    defer allocator.free(encoded);

    const decoded = try b64.decode(encoded, allocator);
    defer allocator.free(decoded);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Original: {s}\n", .{original});
    try stdout.print("Encoded: {s}\n", .{encoded});
    try stdout.print("Decoded: {s}\n", .{decoded});
}

test "we do a lil testing" {
    const allocator = std.testing.allocator;
    const b64 = B64.init();

    const test_cases = [_][]const u8{
        "Hello, World!",
        "test123",
        "",
        "a",
        "ab",
        "abc",
        "a serious matter with some chars!@#$%",
    };

    for (test_cases) |input| {
        const encoded = try b64.encode(input, allocator);
        defer allocator.free(encoded);

        const decoded = try b64.decode(encoded, allocator);
        defer allocator.free(decoded);

        try std.testing.expectEqualStrings(input, decoded);
    }
}
