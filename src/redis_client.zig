const std = @import("std");
const okredis = @import("okredis");

const fs = std.fs;
const log = std.log;
const debug = std.debug;
const mem = std.mem;
const allocator = std.heap.c_allocator;

const Client = okredis.BufferedClient;

export fn redis_client_size() usize {
    return @sizeOf(Client);
}

export fn redis_connect_unix(vessal: *[@sizeOf(Client)]u8, cpath: [*:0]const u8) ?*Client {
    const client = @ptrCast(*Client, @alignCast(@alignOf(Client), vessal));
    const path = mem.span(cpath);
    debug.assert(path.len > 0);

    const stream = std.net.connectUnixSocket(path) catch |err| {
        log.err("open unixsocket failed: {}", .{err});
        return null;
    };
    errdefer stream.close();

    client.init(stream) catch |err| @panic(@errorName(err));

    return client;
}

export fn redis_connect_tcp(vessal: *[@sizeOf(Client)]u8, cip: [*:0]const u8, port: u16) ?*Client {
    const client = @ptrCast(*Client, @alignCast(@alignOf(Client), vessal));
    const ip = mem.span(cip);
    debug.assert(ip.len > 0);

    const addr = std.net.Address.resolveIp(ip, port) catch |err| {
        log.err("resolve address failed: {}", .{err});
        return null;
    };
    const stream = std.net.tcpConnectToAddress(addr) catch |err| {
        log.err("open tcp failed: {}", .{err});
        return null;
    };
    errdefer stream.close();

    client.init(stream) catch |err| @panic(@errorName(err));

    return client;
}

export fn redis_close(client: *Client) void {
    client.close();
}

export fn redis_ping(client: *Client) bool {
    const reply = client.send(okredis.types.FixBuf(4), .{"PING"}) catch |err| {
        log.err("PING failed: {}", .{err});
        return false;
    };
    return mem.eql(u8, reply.toSlice(), "PONG");
}

const ZaddMember = extern struct {
    score: f64,
    value: [*:0]const u8,
};

const ZaddArgs = struct {
    members: []const *const ZaddMember,

    pub const RedisArguments = struct {
        pub fn count(self: ZaddArgs) usize {
            return self.members.len * 2;
        }
        pub fn serialize(self: ZaddArgs, comptime rootSerializer: type, msg: anytype) !void {
            for (self.members) |me| {
                try rootSerializer.serializeArgument(msg, f64, me.score);
                try rootSerializer.serializeArgument(msg, []const u8, mem.span(me.value));
            }
        }
    };
};

export fn redis_zadd(client: *Client, ckey: [*:0]const u8, cmembers: [*]const *const ZaddMember, len: usize) i64 {
    const key = mem.span(ckey);
    const args: ZaddArgs = .{ .members = cmembers[0..len] };

    return client.send(i64, .{ "ZADD", key, args }) catch |err| {
        log.err("ZADD failed: {any}", .{err});
        return 0;
    };
}

export fn redis_del(client: *Client, ckey: [*:0]const u8) bool {
    const key = mem.span(ckey);

    const reply = client.send(okredis.types.OrErr(void), .{ "DEL", key }) catch |err| {
        log.err("DEL failed: {}", .{err});
        return false;
    };
    switch (reply) {
        .Nil => unreachable,
        .Err => |err| {
            log.err("DEL failed: {}", .{err});
            return false;
        },
        .Ok => {
            return true;
        },
    }
}

export fn redis_zcard(client: *Client, ckey: [*:0]const u8) i64 {
    const key = mem.span(ckey);

    return client.send(i64, .{ "ZCARD", key }) catch |err| {
        log.err("ZCARD failed: {}", .{err});
        return 0;
    };
}

export fn redis_zremrangebyrank(client: *Client, ckey: [*:0]const u8, start: i64, stop: i64) i64 {
    const key = mem.span(ckey);
    return client.send(i64, .{ "ZREMRANGEBYRANK", key, start, stop }) catch |err| {
        log.err("ZREMBYRANK failed: {}", .{err});
        return 0;
    };
}

// todo: iterator. offset, count
export fn redis_zrevrange_to_file(client: *Client, ckey: [*:0]const u8, start: i64, stop: i64, cpath: [*:0]const u8) bool {
    const key = mem.span(ckey);
    const path = mem.span(cpath);

    var file = fs.createFileAbsolute(path, .{}) catch |err| {
        log.err("create file failed: {}", .{err});
        return false;
    };
    defer file.close();

    const writer = file.writer();

    const reply = client.sendAlloc([]const []const u8, allocator, .{ "ZRANGE", key, start, stop, "REV" }) catch |err| {
        log.err("ZRANGE failed: {}", .{err});
        return false;
    };
    defer okredis.freeReply(reply, allocator);

    if (reply.len > 0) {
        const last = reply.len - 1;
        for (reply) |member, i| {
            writer.writeAll(member) catch |err| @panic(@errorName(err));
            if (i < last) writer.writeAll("\n") catch |err| @panic(@errorName(err));
        }
    }

    return true;
}

const ZrangeArray = std.ArrayList(u8);

fn zrangeResult(array: *ZrangeArray) [*:0]const u8 {
    array.append(0) catch |err| @panic(@errorName(err));
    const slice = array.toOwnedSliceSentinel(0) catch |err| @panic(@errorName(err));
    return slice.ptr;
}

/// the returned string == "\n".join(members)
/// caller needs to free the returned value using redis_free()
export fn redis_zrevrange(client: *Client, ckey: [*:0]const u8, start: i64, stop: i64) [*:0]const u8 {
    var array = ZrangeArray.init(allocator);
    errdefer array.deinit();

    const key = mem.span(ckey);

    const reply = client.sendAlloc([]const []const u8, allocator, .{ "ZRANGE", key, start, stop, "REV" }) catch |err| {
        log.err("ZRANGE failed: {}", .{err});
        return zrangeResult(&array);
    };
    defer okredis.freeReply(reply, allocator);

    if (reply.len > 0) {
        const last = reply.len - 1;
        for (reply) |member, i| {
            array.appendSlice(member) catch |err| @panic(@errorName(err));
            if (i < last) array.append('\n') catch |err| @panic(@errorName(err));
        }
    }

    return zrangeResult(&array);
}

export fn redis_free(reply: [*:0]const u8) void {
    allocator.destroy(reply);
}
