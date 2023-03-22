const std = @import("std");
const mem = std.mem;
const net = std.net;
const xev = @import("xev");
const global = @import("global.zig");
const lua = @import("ziglua");
const Lua = lua.Lua;
const LuaState = lua.LuaState;
const stream = @import("stream.zig");

/// Connects to given host and port.
pub fn connect(co: *Lua, host: []const u8, port: u16) !c_int {
    const addr = try net.Address.parseIp(host, port);
    const watcher = try xev.TCP.init(addr);

    return stream.scheduleConnect(co, watcher, addr);
}

/// Writes bytes to the stream, returns written length or error in case.
/// This function may not be able to write out fully, if that's the case,
/// recall this function with remaining bytes.
pub fn write(co: *Lua, watcher: xev.TCP, bytes: [:0]const u8) !c_int {
    return stream.scheduleWrite(co, watcher, bytes);
}

// TODO: implement writeAll
// ...

/// Reads bytes from the stream, returns a string on success or error on fail case.
/// This function may not be able to read out fully, if that's the case,
/// recall this function with remaining length.
pub fn read(co: *Lua, watcher: xev.TCP, len: usize) !c_int {
    return stream.scheduleRead(co, watcher, len);
}

/// Close the stream, returns an error string on fail.
pub fn close(co: *Lua, watcher: xev.TCP) !c_int {
    return stream.scheduleClose(co, watcher);
}

// TODO: separate listen call, add additional listen utility for TCP
/// Listen connections to given host and port.
pub fn listen(co: *Lua, host: []const u8, port: u16) !c_int {
    const addr = try net.Address.parseIp(host, port);
    const fd = try xev.TCP.init(addr);

    try fd.bind(addr);
    // TODO: do not use hardcoded kernel backlog size
    try fd.listen(128);

    const ptr = co.newUserdata(xev.TCP);
    ptr.* = fd;
    co.getMetatableRegistry("tcp");
    co.setMetatable(-2);

    return 1;
}

/// Accept new TCP connections.
/// Can only be used with TCP socket that's bind to an host & port and listening connections.
pub fn accept(co: *Lua, watcher: xev.TCP) !c_int {
    const c = try global.getCompletion();
    watcher.accept(
        global.defaultLoop(),
        c,
        LuaState,
        co.state,
        onAcceptFn,
    );

    return co.yield(0);
}

// This is implemented here on purpose, only TCP stack needs this functionality.
fn onAcceptFn(
    state: ?*LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    res: xev.TCP.AcceptError!xev.TCP,
) xev.CallbackAction {
    global.destroyCompletion(c);
    var co = Lua{ .state = state orelse @panic("unknown memory location") };

    const fd = res catch {
        co.pushNil();
        co.pushString("failed accepting incoming connection");
        _ = co.resumeThread(2) catch co.raiseError();

        return .disarm;
    };

    // create a new TCP object for accepted connection
    const ptr = co.newUserdata(xev.TCP);
    ptr.* = fd;
    co.getMetatableRegistry("tcp");
    co.setMetatable(-2);

    _ = co.resumeThread(1) catch co.raiseError();
    return .disarm;
}

// TODO: bikeshed: implement acceptAndSpawn?
// ...
