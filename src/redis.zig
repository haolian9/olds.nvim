const std = @import("std");
const okredis = @import("okredis");

const c = std.c;
const os = std.os;
const fs = std.fs;
const log = std.log;
const debug = std.debug;
const allocator = std.heap.c_allocator;

var maybe_client: ?okredis.Client = null;

export fn redis_connect_unix(cpath: [*:0]const u8) callconv(.C) bool {
    if (maybe_client != null) return false;

    const path = std.mem.span(cpath);
    debug.assert(path.len > 0);

    const stream = std.net.connectUnixSocket(path) catch |err| {
        log.err("open unixsocket failed: {}", .{err});
        return false;
    };
    errdefer stream.close();

    // todo: possiblely avoid this copying?
    var client: okredis.Client = undefined;
    client.init(stream) catch |err| {
        log.err("init client failed: {}", .{err});
        return false;
    };
    maybe_client = client;

    return true;
}

export fn redis_connect_ip(cip: [*:0]const u8, port: u16) callconv(.C) bool {
    if (maybe_client != null) return false;

    const ip = std.mem.span(cip);
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

    var client: okredis.Client = undefined;
    client.init(stream) catch |err| {
        log.err("init client failed: {}", .{err});
        return false;
    };
    maybe_client = client;

    return true;
}

export fn redis_close() void {
    if (maybe_client) |client| client.close();
}

export fn redis_ping() bool {
    const client: *okredis.Client = if (maybe_client) |*cl| cl else return false;
    const reply = client.send(okredis.types.FixBuf(4), .{"PING"}) catch |err| {
        log.err("PING failed: {}", .{err});
        return false;
    };
    return std.mem.eql(u8, reply.toSlice(), "PONG");
}

// todo: variable arguments for score, member
export fn redis_zadd(ckey: [*:0]const u8, score: f64, cmember: [*:0]const u8) i64 {
    const client: *okredis.Client = if (maybe_client) |*cl| cl else return 0;
    const key = std.mem.span(ckey);
    const member = std.mem.span(cmember);

    return client.send(i64, .{ "ZADD", key, score, member }) catch |err| {
        log.err("ZADD failed: {}", .{err});
        return 0;
    };
}

export fn redis_del(ckey: [*:0]const u8) bool {
    const client: *okredis.Client = if (maybe_client) |*cl| cl else return false;
    const key = std.mem.span(ckey);

    switch (client.send(okredis.types.OrErr(void), .{ "DEL", key }) catch |err| {
        log.err("DEL failed: {}", .{err});
        return false;
    }) {
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
    const client: *okredis.Client = if (maybe_client) |*cl| cl else return 0;
    const key = std.mem.span(ckey);

    return client.send(i64, .{ "ZCARD", key }) catch |err| {
        log.err("ZCARD failed: {}", .{err});
        return 0;
    };
}

// todo: redis_zrange
// todo: iterator. offset, count
// todo: no allocating
export fn redis_zrange_to_file(ckey: [*:0]const u8, start: i64, stop: i64, cpath: [*:0]const u8) bool {
    const client: *okredis.Client = if (maybe_client) |*cl| cl else return false;
    const key = std.mem.span(ckey);
    const path = std.mem.span(cpath);

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
