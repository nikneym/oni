const std = @import("std");
const mem = std.mem;
const net = std.net;
const xev = @import("xev");
const global = @import("global.zig");
const lua = @import("ziglua");
const Lua = lua.Lua;
const LuaState = lua.LuaState;

pub const Tcp = struct {
    pub const Userdata = struct {
        fd: xev.TCP,
        reader: struct {
            buffer: *align(8) [4096]u8,
        },
    };

    // TODO: better error messages
    /// Schedules a TCP connect action and suspends the execution of running coroutine.
    pub fn scheduleConnect(co: *Lua, host: []const u8, port: u16) !c_int {
        const addr = try net.Address.parseIp(host, port);
        const fd = try xev.TCP.init(addr);
        const c = try global.getCompletion();

        // schedule the event
        fd.connect(
            global.defaultLoop(),
            c,
            addr,
            LuaState,
            co.state,
            onConnectFn,
        );

        // no need to yield stuff since xev.TCP and xev.Completion is already passed
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
            co.pushString("failed connection to specified address");
            // FIXME: is coroutine status provide necessary info here?
            // give control back to coroutine
            _ = co.resumeThread(2) catch co.raiseError();
            return .disarm;
        };

        // create the TCP object since connection succeeded
        const tcp = co.newUserdata(Userdata);
        tcp.* = .{
            .fd = fd,
            .reader = .{
                .buffer = global.getBuffer() catch {
                    co.pushNil();
                    co.pushString("failed creating write buffer");
                    // FIXME: is coroutine status provide necessary info here?
                    // give control back to coroutine
                    _ = co.resumeThread(2) catch co.raiseError();
                    return .disarm;
                },
            },
        };
        co.getMetatableRegistry("tcp");
        co.setMetatable(-2);

        // all went well, give control back to coroutine
        _ = co.resumeThread(1) catch co.raiseError();
        return .disarm;
    }

    pub fn scheduleWrite(co: *Lua, fd: xev.TCP, bytes: [:0]const u8) !c_int {
        const c = try global.getCompletion();

        fd.write(
            global.defaultLoop(),
            c,
            .{ .slice = bytes },
            LuaState,
            co.state,
            onWriteFn,
        );

        // set the tcp userdata on top
        //co.setTop(-2);
        return co.yield(0);
    }

    fn onWriteFn(
        state: ?*lua.LuaState,
        l: *xev.Loop,
        c: *xev.Completion,
        fd: xev.TCP,
        buf: xev.WriteBuffer,
        res: xev.TCP.WriteError!usize,
    ) xev.CallbackAction {
        global.destroyCompletion(c);

        var co = Lua{ .state = state orelse @panic("unknown memory location") };

        // TODO: notify the coroutine about error
        const len = res catch |e| {
            std.debug.print("{}\n", .{ e });
            return .disarm;
        };

        // couldn't write out the whole buffer
        if (len < buf.slice.len) {
            // reschedule with leftover
            fd.write(
                l,
                c,
                .{ .slice = buf.slice[len..] },
                LuaState,
                co.state,
                onWriteFn,
            );
            return .disarm;
        }
        // buffer is fully written with no errors
        _ = co.resumeThread(0) catch co.raiseError();
        return .disarm;
    }

    // TODO: I really wanted to implement buffering
    // for read operations but I'm in lack of ideas currently
    pub fn scheduleRead(co: *Lua, tcp: *Tcp.Userdata, len: usize) !c_int {
        const c = try global.getCompletion();

        // FIXME: allow reading more than max buffer size
        // FIXME: fix hardcoded values
        tcp.fd.read(
            global.defaultLoop(),
            c,
            .{ .slice = tcp.reader.buffer[0..@min(len, 4096)] },
            LuaState,
            co.state,
            onReadFn,
        );

        return co.yield(0);
    }

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

        var co = Lua{ .state = state.? };

        const len = res catch |e| {
            co.pushNil(); // push nil for the string part
            switch (e) {
                // EOF is presented in all libxev backends
                error.EOF => co.pushString("end of stream"),
                else => co.pushString("failed reading from the stream"),
            }

            _ = co.resumeThread(2) catch co.raiseError();
            return .disarm;
        };

        // success, push the bytes
        co.pushBytes(buf.slice[0..len]);
        _ = co.resumeThread(1) catch co.raiseError();
        return .disarm;
    }

    /// Schedules a close event
    pub fn scheduleClose(co: *Lua, tcp: *Tcp.Userdata) !c_int {
        const c = try global.getCompletion();

        tcp.fd.close(
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

        var co = Lua{ .state = state.? };

        res catch {
            co.pushString("unable to close the TCP connection");
            _ = co.resumeThread(1) catch co.raiseError();
            return .disarm;
        };

        _ = co.resumeThread(0) catch co.raiseError();
        return .disarm;
    }

    /// Create a new TCP server that listens the specified address.
    pub fn createTcpListener(co: *Lua, host: []const u8, port: u16) !c_int {
        const addr = try net.Address.parseIp(host, port);
        const fd = try xev.TCP.init(addr);

        try fd.bind(addr);
        // TODO: do not use hardcoded kernel backlog size
        try fd.listen(128);

        const tcp = co.newUserdata(Userdata);
        tcp.* = .{
            .fd = fd,
            .reader = .{
                .buffer = global.getBuffer() catch {
                    co.pushNil();
                    co.pushString("failed creating write buffer");
                    return 2;
                },
            },
        };
        co.getMetatableRegistry("tcp");
        co.setMetatable(-2);

        return 1;
    }

    /// Schedules an accept event on TCP Listener.
    pub fn scheduleAccept(co: *Lua, tcp: *Tcp.Userdata) !c_int {
        const c = try global.getCompletion();

        tcp.fd.accept(
            global.defaultLoop(),
            c,
            LuaState,
            co.state,
            onAcceptFn,
        );

        return co.yield(0);
    }

    fn onAcceptFn(
        state: ?*LuaState,
        _: *xev.Loop,
        c: *xev.Completion,
        res: xev.TCP.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        global.destroyCompletion(c);
        var co = Lua{ .state = state.? };

        const fd = res catch {
            co.pushNil();
            co.pushString("failed accepting incoming connection");
            _ = co.resumeThread(2) catch co.raiseError();

            return .disarm;
        };

        // create a new TCP object for accepted connection
        const tcp = co.newUserdata(Userdata);
        tcp.* = .{
            .fd = fd,
            .reader = .{
                .buffer = global.getBuffer() catch {
                    co.pushNil();
                    co.pushString("failed creating write buffer");
                    _ = co.resumeThread(2) catch co.raiseError();

                    return .disarm;
                },
            },
        };
        co.getMetatableRegistry("tcp");
        co.setMetatable(-2);

        _ = co.resumeThread(1) catch co.raiseError();
        return .disarm;
    }
};
