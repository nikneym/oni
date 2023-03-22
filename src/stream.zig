const std = @import("std");
const net = std.net;
const xev = @import("xev");
const lua = @import("ziglua");
const Lua = lua.Lua;
const LuaState = lua.LuaState;
const global = @import("global.zig");

/// Schedules a connect action and yields the execution of the given coroutine.
/// Can give unexpected results with watchers other than xev.TCP.
/// This function must be the return expression of the caller.
pub fn scheduleConnect(co: *Lua, watcher: anytype, addr: net.Address) !c_int {
    const c = try global.getCompletion();
    watcher.connect(
        global.defaultLoop(),
        c,
        addr,
        LuaState,
        co.state,
        onConnectFn,
    );

    return co.yield(0);
}

fn onConnectFn(
    state: ?*LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    fd: xev.TCP,
    res: xev.TCP.ConnectError!void,
) xev.CallbackAction {
    // its safe to destroy this here, I know what I'm doing
    global.destroyCompletion(c);

    // get the VM
    var co = Lua{ .state = state orelse @panic("unknown memory location") };

    // since libxev returns different errors for different backends,
    // it's hard to return specific errors. So currently we will send
    // one unified error to Lua VM
    res catch {
        co.pushNil();
        co.pushString("failed to connect to specified address");
        // FIXME: do coroutine status provide necessary info here?
        // give control back to coroutine
        _ = co.resumeThread(2) catch co.raiseError();
        return .disarm;
    };

    // create the TCP object since connection succeeded
    const tcp = co.newUserdata(xev.TCP);
    tcp.* = fd;
    co.getMetatableRegistry("tcp");
    co.setMetatable(-2);

    // all went well, give control back to coroutine
    _ = co.resumeThread(1) catch co.raiseError();
    return .disarm;
}

/// Schedules a write action and yields the execution of the given coroutine.
/// This function must be the return expression of the caller.
pub fn scheduleWrite(co: *Lua, watcher: anytype, bytes: [:0]const u8) !c_int {
    const c = try global.getCompletion();
    watcher.write(
        global.defaultLoop(),
        c,
        .{ .slice = bytes },
        LuaState,
        co.state,
        onWriteFn,
    );

    return co.yield(0);
}

fn onWriteFn(
    state: ?*lua.LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    _: xev.TCP,
    _: xev.WriteBuffer,
    res: xev.TCP.WriteError!usize,
) xev.CallbackAction {
    global.destroyCompletion(c);

    // get the VM
    var co = Lua{ .state = state orelse @panic("unknown memory location") };

    const len = res catch {
        co.pushNil();
        co.pushString("unable to write to the stream");
        _ = co.resumeThread(2) catch co.raiseError();

        return .disarm;
    };

    // resume back and give the written length to coroutine
    co.pushInteger(@intCast(lua.Integer, len));
    _ = co.resumeThread(1) catch co.raiseError();
    return .disarm;
}

/// Schedules a read action and yields the execution of the given coroutine.
/// This function must be the return expression of the caller.
pub fn scheduleRead(co: *Lua, watcher: anytype, len: usize) !c_int {
    const c = try global.getCompletion();
    const buffer = try global.getBuffer();

    // FIXME: fix hardcoded values
    watcher.read(
        global.defaultLoop(),
        c,
        .{ .slice = buffer[0..@min(len, buffer.len)] },
        LuaState,
        co.state,
        onReadFn,
    );

    return co.yield(0);
}

// TODO: deallocate buf
fn onReadFn(
    state: ?*lua.LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    _: xev.TCP,
    buf: xev.ReadBuffer,
    res: xev.TCP.ReadError!usize,
) xev.CallbackAction {
    // put the completion back to memory pool
    global.destroyCompletion(c);

    var co = Lua{ .state = state orelse @panic("unknown memory location") };

    const len = res catch |e| {
        co.pushNil(); // push nil for the string part
        switch (e) {
            // EOF is presented in all libxev backends
            error.EOF => co.pushString("end of stream"),
            else => co.pushString("unable to read from the stream"),
        }

        _ = co.resumeThread(2) catch co.raiseError();
        return .disarm;
    };

    // success, push the bytes
    co.pushBytes(buf.slice[0..len]);
    _ = co.resumeThread(1) catch co.raiseError();
    return .disarm;
}

// FIXME: should this function suspend the execution?
/// Schedules a close action and yields the execution of the given coroutine.
/// This function must be the return expression of the caller.
pub fn scheduleClose(co: *Lua, watcher: anytype) !c_int {
    const c = try global.getCompletion();

    watcher.close(
        global.defaultLoop(),
        c,
        LuaState,
        co.state,
        onCloseFn,
    );

    return co.yield(0);
}

fn onCloseFn(
    state: ?*lua.LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    _: xev.TCP,
    res: xev.TCP.CloseError!void,
) xev.CallbackAction {
    global.destroyCompletion(c);

    var co = Lua{ .state = state orelse @panic("unknown memory location") };

    res catch {
        co.pushString("unable to close the stream");
        _ = co.resumeThread(1) catch co.raiseError();
        return .disarm;
    };

    _ = co.resumeThread(0) catch co.raiseError();
    return .disarm;
}
