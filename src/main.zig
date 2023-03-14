const std = @import("std");
const print = std.debug.print;

const okredis = @import("okredis");

pub fn main() !void {
    var stream_closed = false;
    const stream = try std.net.connectUnixSocket("/run/user/1000/redis.sock");
    errdefer if (!stream_closed) stream.close();

    var client: okredis.Client = undefined;
    try client.init(stream);
    defer {
        client.close();
        stream_closed = true;
    }

    // {
    //     const expect = "PONG";
    //     const reply = try client.send(okredis.types.FixBuf(expect.len), .{"ping"});
    //     print("len=actually:{d},buf:{d} {s}\n", .{ reply.len, reply.buf.len, std.fmt.fmtSliceEscapeLower(&reply.buf) });
    //     // print("len=actually:{d},buf:{d} {s}\n", .{ reply.len, reply.buf.len, reply.toSlice() });
    // }

    {
        const reply = try client.send(i64, .{ "ZADD", "fruits", "NX", 1, "apple", 2, "orange", 3, "banana", 4, "blue berry" });
        print("affected entries={d}\n", .{reply});
    }

    {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const reply = try client.sendAlloc([]const []const u8, arena.allocator(), .{ "ZRANGE", "fruits", 0, 9 });
        // print("{any}\n", .{reply});
        for (reply) |member| {
            print("{s}\n", .{member});
        }
    }
}
