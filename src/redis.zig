const std = @import("std");
const okredis = @import("okredis");

const fs = std.fs;
const log = std.log;
const debug = std.debug;
const mem = std.mem;
const allocator = std.heap.c_allocator;

const Client = okredis.BufferedClient;

var global_client: ?*Client = null;

fn initGlobalClient(stream: std.net.Stream) bool {
    const client = allocator.create(Client) catch |err| {
        log.err("allocate memory failed: {}", .{err});
        return false;
    };
    client.init(stream) catch |err| {
        log.err("init client failed: {}", .{err});
        return false;
    };
    global_client = client;
    return true;
}

export fn redis_connect_unix(cpath: [*:0]const u8) bool {
    if (global_client != null) return false;

    const path = mem.span(cpath);
    debug.assert(path.len > 0);

    const stream = std.net.connectUnixSocket(path) catch |err| {
        log.err("open unixsocket failed: {}", .{err});
        return false;
    };
    errdefer stream.close();

    return initGlobalClient(stream);
}

export fn redis_connect_ip(cip: [*:0]const u8, port: u16) bool {
    if (global_client != null) return false;

    const ip = mem.span(cip);
    debug.assert(ip.len > 0);

    const addr = std.net.Address.resolveIp(ip, port) catch |err| {
        log.err("resolve address failed: {}", .{err});
        return false;
    };
    const stream = std.net.tcpConnectToAddress(addr) catch |err| {
        log.err("open tcp failed: {}", .{err});
        return false;
    };
    errdefer stream.close();

    return initGlobalClient(stream);
}

export fn redis_close() void {
    if (global_client) |client| {
        client.close();
        allocator.destroy(client);
        global_client = null;
    }
}

export fn redis_ping() bool {
    const client: *Client = if (global_client) |cl| cl else return false;
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

export fn redis_zadd(ckey: [*:0]const u8, cmembers: [*]const *const ZaddMember, len: usize) i64 {
    const client: *Client = if (global_client) |cl| cl else return 0;
    const key = mem.span(ckey);
    const args: ZaddArgs = .{ .members = cmembers[0..len] };

    return client.send(i64, .{ "ZADD", key, args }) catch |err| {
        log.err("ZADD failed: {any}", .{err});
        return 0;
    };
}

export fn redis_del(ckey: [*:0]const u8) bool {
    const client: *Client = if (global_client) |cl| cl else return false;
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

export fn redis_zcard(ckey: [*:0]const u8) i64 {
    const client: *Client = if (global_client) |cl| cl else return 0;
    const key = mem.span(ckey);

    return client.send(i64, .{ "ZCARD", key }) catch |err| {
        log.err("ZCARD failed: {}", .{err});
        return 0;
    };
}

export fn redis_zremrangebyrank(ckey: [*:0]const u8, start: i64, stop: i64) i64 {
    const client: *Client = if (global_client) |cl| cl else return 0;
    const key = mem.span(ckey);
    return client.send(i64, .{ "ZREMRANGEBYRANK", key, start, stop }) catch |err| {
        log.err("ZREMBYRANK failed: {}", .{err});
        return 0;
    };
}

// todo: redis_zrange
// todo: iterator. offset, count
// todo: no allocating
export fn redis_zrevrange_to_file(ckey: [*:0]const u8, start: i64, stop: i64, cpath: [*:0]const u8) bool {
    const client: *Client = if (global_client) |cl| cl else return false;
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

    for (reply) |member| {
        writer.writeAll(member) catch |err| {
            log.err("write file failed: {}", .{err});
            return false;
        };
        writer.writeAll("\n") catch |err| {
            log.err("write file failed: {}", .{err});
            return false;
        };
    }

    return true;
}
